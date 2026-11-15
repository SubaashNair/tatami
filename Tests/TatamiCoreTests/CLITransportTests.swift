import XCTest
import Darwin
@testable import TatamiCore

/// The local socket behind the `tatami` command. These tests use real Unix sockets in a private folder under /tmp.
final class CLITransportTests: XCTestCase {
    private var folder = ""
    private var server: CLIServer?
    private var path: String { folder + "/s.sock" }

    override func setUpWithError() throws {
        folder = "/tmp/tatami-test-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    override func tearDown() {
        server?.stop()
        try? FileManager.default.removeItem(atPath: folder)
    }

    private func startEcho(readTimeout: TimeInterval = 2) throws {
        let echo = CLIServer(path: path, readTimeout: readTimeout) { request in .success(request.args.joined(separator: " ")) }
        try echo.start()
        server = echo
    }

    private func mode(_ file: String) -> mode_t {
        var info = stat()
        XCTAssertEqual(stat(file, &info), 0)
        return info.st_mode & 0o777
    }

    private func address(_ socketPath: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { strncpy($0, socketPath, 103) }
        }
        return address
    }

    private func connectRaw() -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var target = address(path)
        let result = withUnsafePointer(to: &target) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        XCTAssertEqual(result, 0)
        return fd
    }

    // MARK: working

    func testARequestGetsItsReply() throws {
        try startEcho()
        let reply = try CLIClient.send(CLIRequest(args: ["focus", "left"]), path: path, timeout: 5)
        XCTAssertTrue(reply.ok)
        XCTAssertEqual(reply.output, "focus left")
    }

    func testManyRequestsInARowAllGetReplies() throws {
        try startEcho()
        for index in 0..<20 {
            XCTAssertEqual(try CLIClient.send(CLIRequest(args: ["n\(index)"]), path: path, timeout: 5).output, "n\(index)")
        }
    }

    func testStoppingRemovesTheSocketAndNothingIsListeningAfterwards() throws {
        try startEcho()
        server?.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertThrowsError(try CLIClient.send(CLIRequest(args: ["status"]), path: path, timeout: 2)) { error in
            XCTAssertEqual(error as? CLIClientError, .notRunning)
        }
    }

    func testNothingRunningMeansNotRunning() {
        XCTAssertThrowsError(try CLIClient.send(CLIRequest(args: ["status"]), path: path, timeout: 2)) { error in
            XCTAssertEqual(error as? CLIClientError, .notRunning)
        }
    }

    // MARK: private to this user

    func testTheSocketFileIsOnlyAccessibleToItsOwner() throws {
        try startEcho()
        XCTAssertEqual(mode(path), 0o600)
    }

    func testAMissingFolderIsCreatedPrivate() throws {
        let nested = folder + "/a/b/s.sock"
        let own = CLIServer(path: nested) { _ in .success() }
        try own.start()
        defer { own.stop() }
        XCTAssertEqual(mode(folder + "/a/b"), 0o700)
    }

    func testOurOwnFolderWithLoosePermissionsIsTightened() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder)
        try startEcho()
        XCTAssertEqual(mode(folder), 0o700)
    }

    func testPeersAreCheckedAgainstTheCurrentUser() {
        var pair: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
        defer { close(pair[0]); close(pair[1]) }
        XCTAssertTrue(CLIServer.isSameUser(pair[0]))
        XCTAssertFalse(CLIServer.isSameUser(-1))
    }

    // MARK: stale files

    func testALeftoverSocketFromACrashIsReplaced() throws {
        // Bind a socket and close it without removing the file, as a crash would.
        let stale = socket(AF_UNIX, SOCK_STREAM, 0)
        var target = address(path)
        let bound = withUnsafePointer(to: &target) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(stale, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        XCTAssertEqual(bound, 0)
        close(stale)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        try startEcho()
        XCTAssertEqual(try CLIClient.send(CLIRequest(args: ["ok"]), path: path, timeout: 5).output, "ok")
    }

    func testAnotherFileAtThePathIsNeverDeleted() throws {
        try Data("precious".utf8).write(to: URL(fileURLWithPath: path))
        let own = CLIServer(path: path) { _ in .success() }
        XCTAssertThrowsError(try own.start()) { XCTAssertEqual($0 as? CLIServer.StartError, .pathInUse) }
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "precious")
    }

    func testASecondServerCannotTakeOverALiveSocket() throws {
        try startEcho()
        let second = CLIServer(path: path) { _ in .success("intruder") }
        XCTAssertThrowsError(try second.start()) { XCTAssertEqual($0 as? CLIServer.StartError, .pathInUse) }
        XCTAssertEqual(try CLIClient.send(CLIRequest(args: ["who"]), path: path, timeout: 5).output, "who")
    }

    func testATooLongPathIsRefused() {
        let long = CLIServer(path: folder + "/" + String(repeating: "x", count: 120) + ".sock") { _ in .success() }
        XCTAssertThrowsError(try long.start()) { XCTAssertEqual($0 as? CLIServer.StartError, .pathTooLong) }
    }

    // MARK: hostile or broken clients

    func testGarbageGetsAnErrorReplyAndTheServerKeepsWorking() throws {
        try startEcho()
        let reply = try CLIClient.exchange(Data("this is not json\n".utf8), path: path, timeout: 5)
        XCTAssertFalse(reply.ok)
        XCTAssertNotNil(reply.error)
        XCTAssertEqual(try CLIClient.send(CLIRequest(args: ["still", "alive"]), path: path, timeout: 5).output, "still alive")
    }

    func testAnOversizedRequestIsRefusedWithoutBeingRead() throws {
        try startEcho()
        let huge = Data(repeating: UInt8(ascii: "a"), count: CLIProtocol.maxRequestBytes * 4)  // no newline, far over the limit
        let reply = try CLIClient.exchange(huge, path: path, timeout: 5)
        XCTAssertFalse(reply.ok)
        XCTAssertTrue(reply.error?.contains("large") == true, reply.error ?? "no error")
        XCTAssertEqual(try CLIClient.send(CLIRequest(args: ["after"]), path: path, timeout: 5).output, "after")
    }

    func testANewerClientIsToldToUpdate() throws {
        try startEcho()
        let reply = try CLIClient.exchange(Data(#"{"version":9,"args":["status"]}"#.utf8 + [10]), path: path, timeout: 5)
        XCTAssertFalse(reply.ok)
        XCTAssertTrue(reply.error?.contains("version") == true, reply.error ?? "no error")
    }

    func testAClientThatSendsNothingCannotBlockOthersAndIsCutOff() throws {
        try startEcho(readTimeout: 0.3)
        let idle = connectRaw()
        defer { close(idle) }
        // Another client is served at once while the idle one is still connected.
        XCTAssertEqual(try CLIClient.send(CLIRequest(args: ["quick"]), path: path, timeout: 5).output, "quick")
        // The idle one is dropped after the read timeout instead of holding the server forever.
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(idle, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var buffer = [UInt8](repeating: 0, count: 256)
        let started = Date()
        _ = read(idle, &buffer, buffer.count)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.5)
    }

    func testAHandlerThatIsSlowDoesNotStopTheServer() throws {
        let release = DispatchSemaphore(value: 0)
        let slow = CLIServer(path: path) { request in
            if request.args == ["slow"] { _ = release.wait(timeout: .now() + 3) }
            return .success(request.args.joined(separator: " "))
        }
        try slow.start()
        server = slow
        DispatchQueue.global().async { _ = try? CLIClient.send(CLIRequest(args: ["slow"]), path: self.path, timeout: 5) }
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(try CLIClient.send(CLIRequest(args: ["fast"]), path: path, timeout: 5).output, "fast")
        release.signal()
    }

    // MARK: hostile clients

    func testAClientThatDripsBytesIsCutOffByTheTotalDeadline() throws {
        try startEcho(readTimeout: 0.5)
        let dripper = connectRaw()
        defer { close(dripper) }
        var noSignal: Int32 = 1
        setsockopt(dripper, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 4, tv_usec: 0)
        setsockopt(dripper, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let started = Date()
        var cutOff = false
        while Date().timeIntervalSince(started) < 3 {
            var byte: UInt8 = 0x20
            if write(dripper, &byte, 1) < 0 { cutOff = true; break }
            Thread.sleep(forTimeInterval: 0.15)
        }
        // Either a write failed or the server hung up; both mean it did not wait for the drip forever.
        var buffer = [UInt8](repeating: 0, count: 256)
        let count = read(dripper, &buffer, buffer.count)
        XCTAssertTrue(cutOff || count >= 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.5)
    }

    func testTooManyConnectionsAreTurnedAwayAndTheServerRecovers() throws {
        let capped = CLIServer(path: path, readTimeout: 5, maxClients: 2) { .success($0.args.joined(separator: " ")) }
        try capped.start()
        server = capped
        let idle = [connectRaw(), connectRaw()]
        Thread.sleep(forTimeInterval: 0.3)
        // Turned away with a reply that says why, not a hang-up the client would report as a bad reply.
        let refused = try CLIClient.send(CLIRequest(args: ["x"]), path: path, timeout: 2)
        XCTAssertFalse(refused.ok)
        XCTAssertTrue(refused.error?.contains("busy") == true)
        idle.forEach { close($0) }
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(try CLIClient.send(CLIRequest(args: ["again"]), path: path, timeout: 5).output, "again")
    }

    func testStoppingNeverRemovesASocketThatIsNotOurs() throws {
        try startEcho()
        unlink(path)
        let other = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(other) }
        var target = address(path)
        let bound = withUnsafePointer(to: &target) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(other, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        XCTAssertEqual(bound, 0)
        server?.stop()
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }
}

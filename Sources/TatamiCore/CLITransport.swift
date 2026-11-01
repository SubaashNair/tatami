import Foundation
import Darwin

// The local socket behind the `tatami` command. It is private to the user: the folder is 0700, the socket file is 0600,
// every connection is checked to come from the same user, requests are size limited, and slow clients are cut off.
// There is no network access of any kind, and nothing here can run a program.

public enum CLIClientError: Error, Equatable {
    case notRunning, timedOut, badReply, tooLarge
}

/// A `sockaddr_un` for a path, or nil when it does not fit.
private func unixAddress(_ path: String) -> sockaddr_un? {
    let capacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
    guard path.utf8.count < capacity else { return nil }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strlcpy($0, path, capacity) }
    }
    return address
}

private func connectUnix(_ fd: Int32, _ address: inout sockaddr_un) -> Int32 {
    withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
}

private func setTimeouts(_ fd: Int32, _ seconds: TimeInterval) {
    var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000))
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
}

private func writeAll(_ fd: Int32, _ data: Data) {
    data.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
            let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
            if written > 0 { offset += written } else if written < 0 && errno == EINTR { continue } else { return }
        }
    }
}

public enum CLIClient {
    public static func send(_ request: CLIRequest, path: String, timeout: TimeInterval = 10) throws -> CLIResponse {
        try exchange(CLICodec.encode(request), path: path, timeout: timeout)
    }

    /// Sends raw bytes and reads one reply. Write errors are ignored on purpose: a server may answer and hang up early.
    static func exchange(_ bytes: Data, path: String, timeout: TimeInterval) throws -> CLIResponse {
        guard var target = unixAddress(path) else { throw CLIClientError.notRunning }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CLIClientError.notRunning }
        defer { close(fd) }
        setTimeouts(fd, timeout)
        guard connectUnix(fd, &target) == 0 else { throw CLIClientError.notRunning }
        guard CLIServer.isSameUser(fd) else { throw CLIClientError.notRunning }  // never talk to another user's socket
        writeAll(fd, bytes)
        shutdown(fd, SHUT_WR)
        var reply = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        readLoop: while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                reply.append(buffer, count: count)
                if reply.count > CLIProtocol.maxResponseBytes { throw CLIClientError.tooLarge }
            } else if count == 0 {
                break readLoop
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                if reply.isEmpty { throw CLIClientError.timedOut }
                break readLoop
            } else {
                break readLoop  // a reset after a reply was sent still leaves the reply
            }
        }
        guard !reply.isEmpty, let response = try? CLICodec.decodeResponse(reply) else { throw CLIClientError.badReply }
        return response
    }
}

public final class CLIServer: @unchecked Sendable {
    public enum StartError: Error, Equatable { case pathInUse, pathTooLong, unsafeFolder, system(Int32) }

    private let path: String
    private let readTimeout: TimeInterval
    private let maxClients: Int
    private var activeClients = 0
    private var boundFile: (device: dev_t, inode: ino_t)?
    private let handler: @Sendable (CLIRequest) async -> CLIResponse
    private let acceptQueue = DispatchQueue(label: "app.tatami.cli.accept")
    private let clientQueue = DispatchQueue(label: "app.tatami.cli.clients", attributes: .concurrent)
    private let lock = NSLock()
    private var source: DispatchSourceRead?

    /// `readTimeout` is the total time a client gets to send its request, not the gap between bytes.
    public init(path: String, readTimeout: TimeInterval = 2, maxClients: Int = 8, handler: @escaping @Sendable (CLIRequest) async -> CLIResponse) {
        self.path = path
        self.readTimeout = readTimeout
        self.maxClients = maxClients
        self.handler = handler
    }

    deinit { stop() }

    /// True when the process on the other end of a connected socket runs as the current user.
    static func isSameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0, gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }

    // MARK: starting and stopping

    public func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard source == nil else { return }
        guard var target = unixAddress(path) else { throw StartError.pathTooLong }
        try prepareFolder()
        try clearStaleSocket()

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.system(errno) }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        // The folder is 0700 and ours, so nobody else can reach the socket file even before the chmod below.
        let bound = withUnsafePointer(to: &target) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        let bindError = errno
        guard bound == 0 else { close(fd); throw bindError == EADDRINUSE ? StartError.pathInUse : StartError.system(bindError) }
        chmod(path, 0o600)
        var made = stat()
        if lstat(path, &made) == 0 { boundFile = (made.st_dev, made.st_ino) }
        guard listen(fd, 8) == 0 else { let error = errno; close(fd); unlink(path); throw StartError.system(error) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        reader.setEventHandler { [weak self] in self?.acceptReady(fd) }
        reader.setCancelHandler { close(fd) }
        reader.resume()
        source = reader
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard let reader = source else { return }
        reader.cancel()
        source = nil
        var info = stat()
        // Only the socket this server created is removed, never one that replaced it.
        if lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == getuid(),
           info.st_dev == boundFile?.device, info.st_ino == boundFile?.inode { unlink(path) }
        boundFile = nil
    }

    /// The folder must be ours and private. One owned by someone else, or a symlink, is refused.
    private func prepareFolder() throws {
        let folder = (path as NSString).deletingLastPathComponent
        var info = stat()
        if lstat(folder, &info) != 0 {
            do { try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            catch { throw StartError.unsafeFolder }
            guard lstat(folder, &info) == 0 else { throw StartError.unsafeFolder }
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else { throw StartError.unsafeFolder }
        if info.st_mode & 0o077 != 0, chmod(folder, 0o700) != 0 { throw StartError.unsafeFolder }
    }

    /// Removes a socket left by a crash. Anything else at the path, or a socket that still answers, is left alone.
    private func clearStaleSocket() throws {
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == getuid() else { throw StartError.pathInUse }
        guard var target = unixAddress(path) else { throw StartError.pathTooLong }
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { if probe >= 0 { close(probe) } }
        if probe >= 0, connectUnix(probe, &target) == 0 { throw StartError.pathInUse }
        unlink(path)
    }

    // MARK: serving

    private func acceptReady(_ listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 { return }
            _ = fcntl(client, F_SETFD, FD_CLOEXEC)
            guard admitClient() else { close(client); continue }
            clientQueue.async { [self] in serve(client) }
        }
    }

    private func admitClient() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard activeClients < maxClients else { return false }
        activeClients += 1
        return true
    }

    private func finish(_ fd: Int32) {
        close(fd)
        lock.lock(); activeClients -= 1; lock.unlock()
    }

    private enum Read { case nothing, reply(CLIResponse), request(CLIRequest) }

    private func serve(_ fd: Int32) {
        guard Self.isSameUser(fd) else { finish(fd); return }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)  // accepted sockets can inherit non-blocking mode
        setTimeouts(fd, readTimeout)
        switch readRequest(fd) {
        case .nothing:
            finish(fd)
        case .reply(let response):
            Self.reply(response, on: fd)
            finish(fd)
        case .request(let request):
            let handler = self.handler
            Task.detached { [self] in
                let response = await handler(request)
                // Writing can block on a client that never reads, so it must not run on the shared async pool.
                clientQueue.async { [self] in
                    Self.reply(response, on: fd)
                    finish(fd)
                }
            }
        }
    }

    /// Reads up to a newline or end of stream, never more than the limit.
    private func readRequest(_ fd: Int32) -> Read {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(readTimeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return data.isEmpty ? .nothing : .reply(.failure("The request timed out.")) }
            setTimeouts(fd, max(remaining, 0.001))  // each read may only wait for what is left of the total allowance
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if data.count > CLIProtocol.maxRequestBytes { return .reply(.failure("The request is too large.")) }
                if let newline = data.firstIndex(of: 10) { data = data.prefix(upTo: newline); break }
            } else if count == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                return data.isEmpty ? .nothing : .reply(.failure("The request timed out."))  // a client that sends nothing is just dropped
            }
        }
        guard !data.isEmpty else { return .nothing }
        switch CLIRequest.decode(data) {
        case .success(let request): return .request(request)
        case .failure(.tooLarge): return .reply(.failure("The request is too large."))
        case .failure(.malformed): return .reply(.failure("The request is malformed."))
        case .failure(.unsupportedVersion(let version)):
            return .reply(.failure("This app speaks command protocol version \(CLIProtocol.version), but the tatami command sent version \(version). Update both to the same release."))
        }
    }

    private static func reply(_ response: CLIResponse, on fd: Int32) {
        var data = (try? CLICodec.encode(response)) ?? Data()
        if data.isEmpty || data.count > CLIProtocol.maxResponseBytes { data = (try? CLICodec.encode(CLIResponse.failure("The reply is too large."))) ?? Data() }
        writeAll(fd, data)
    }
}

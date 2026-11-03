import XCTest
@testable import TatamiCore

/// The `tatami` command: its request format, the command parser, output formatting and the socket path.
final class CLIProtocolTests: XCTestCase {
    // MARK: request and reply format

    func testARequestSurvivesEncodingAndDecoding() throws {
        let request = CLIRequest(args: ["focus", "left"])
        let line = try CLICodec.encode(request)
        XCTAssertEqual(line.last, UInt8(ascii: "\n"))  // one JSON document per line
        XCTAssertEqual(try CLIRequest.decode(line).get(), request)
    }

    func testMalformedInputIsRejected() {
        XCTAssertEqual(CLIRequest.decode(Data("not json".utf8)), .failure(.malformed))
        XCTAssertEqual(CLIRequest.decode(Data()), .failure(.malformed))
        XCTAssertEqual(CLIRequest.decode(Data(#"{"version":1}"#.utf8)), .failure(.malformed))  // no args
    }

    func testANewerProtocolVersionIsRefusedWithItsNumber() {
        XCTAssertEqual(CLIRequest.decode(Data(#"{"version":2,"args":["status"]}"#.utf8)), .failure(.unsupportedVersion(2)))
    }

    func testOversizedRequestsAreRefused() {
        let big = Data(repeating: UInt8(ascii: "a"), count: CLIProtocol.maxRequestBytes + 1)
        XCTAssertEqual(CLIRequest.decode(big), .failure(.tooLarge))
        let manyArgs = CLIRequest(args: Array(repeating: "x", count: CLIProtocol.maxArguments + 1))
        XCTAssertEqual(CLIRequest.decode((try? CLICodec.encode(manyArgs)) ?? Data()), .failure(.tooLarge))
    }

    func testAReplyCarriesSuccessAndFailure() throws {
        let ok = try CLICodec.decodeResponse(CLICodec.encode(CLIResponse.success("done")))
        XCTAssertTrue(ok.ok); XCTAssertEqual(ok.output, "done"); XCTAssertNil(ok.error)
        let failed = try CLICodec.decodeResponse(CLICodec.encode(CLIResponse.failure("nope")))
        XCTAssertFalse(failed.ok); XCTAssertEqual(failed.error, "nope")
    }

    // MARK: the command parser

    private func parse(_ words: String...) -> Result<CLICommand, CLIParseError> { CLICommand.parse(words) }

    func testRoomToDisplayTakesNextOrPrevious() {
        XCTAssertEqual(parse("room-to-display", "next"), .success(.roomToDisplay(1)))
        XCTAssertEqual(parse("ROOM-TO-DISPLAY", "PREV"), .success(.roomToDisplay(-1)))
        for words in [["room-to-display"], ["room-to-display", "2"], ["room-to-display", "next", "x"]] {
            if case .success = CLICommand.parse(words) { XCTFail("\(words) must not parse") }
        }
    }

    func testRoomBackGoesToThePreviousRoom() {
        XCTAssertEqual(parse("room", "back"), .success(.roomBack))
        XCTAssertEqual(parse("ROOM", "BACK"), .success(.roomBack))
        if case .success = parse("room", "back", "1") { XCTFail("extra arguments must be refused") }
    }

    func testRoomCommands() {
        XCTAssertEqual(parse("room", "3"), .success(.stage(3)))
        XCTAssertEqual(parse("room", "next"), .success(.stageStep(1)))
        XCTAssertEqual(parse("room", "prev"), .success(.stageStep(-1)))
        // "stage" was the old word and keeps working
        XCTAssertEqual(parse("stage", "3"), .success(.stage(3)))
        XCTAssertEqual(parse("STAGE", "next"), .success(.stageStep(1)))
        XCTAssertEqual(parse("send", "2"), .success(.send(2)))
        for bad in ["0", "10", "-1", "two", ""] {
            if case .success = parse("room", bad) { XCTFail("room \(bad) must not parse") }
        }
        if case .success = parse("send", "0") { XCTFail("send 0 must not parse") }
    }

    func testFocusAndMoveTakeADirection() {
        XCTAssertEqual(parse("focus", "left"), .success(.focus(.left)))
        XCTAssertEqual(parse("focus", "down"), .success(.focus(.down)))
        XCTAssertEqual(parse("move", "up"), .success(.move(.up)))
        XCTAssertEqual(parse("move", "right"), .success(.move(.right)))
        if case .success = parse("focus", "sideways") { XCTFail("unknown direction must not parse") }
    }

    func testWindowPaneAndDisplayCommands() {
        XCTAssertEqual(parse("window", "next"), .success(.cycle(1)))
        XCTAssertEqual(parse("window", "prev"), .success(.cycle(-1)))
        XCTAssertEqual(parse("pane", "4"), .success(.pane(4)))
        XCTAssertEqual(parse("move-to-pane", "9"), .success(.movePane(9)))
        XCTAssertEqual(parse("display", "next"), .success(.display(1)))
        XCTAssertEqual(parse("display", "prev"), .success(.display(-1)))
        if case .success = parse("pane", "10") { XCTFail("pane 10 must not parse") }
    }

    func testCommandsWithoutArguments() {
        XCTAssertEqual(parse("float"), .success(.float))
        XCTAssertEqual(parse("float-app"), .success(.floatApp))
        XCTAssertEqual(parse("rotate"), .success(.rotate))
        XCTAssertEqual(parse("tiles"), .success(.tiles))
        XCTAssertEqual(parse("undo-layout"), .success(.undoLayout))
        XCTAssertEqual(parse("rescue"), .success(.rescue))
        XCTAssertEqual(parse("start"), .success(.start))
        XCTAssertEqual(parse("pause"), .success(.pause))
    }

    func testQueriesAcceptAJsonFlag() {
        XCTAssertEqual(parse("list", "windows"), .success(.list(.windows, json: false)))
        XCTAssertEqual(parse("list", "rooms", "--json"), .success(.list(.rooms, json: true)))
        XCTAssertEqual(parse("list", "stages"), .success(.list(.rooms, json: false)))  // the old word still works
        XCTAssertEqual(parse("list", "displays"), .success(.list(.displays, json: false)))
        XCTAssertEqual(parse("status"), .success(.status(json: false)))
        XCTAssertEqual(parse("status", "--json"), .success(.status(json: true)))
    }

    func testBadInputGivesAUsefulError() {
        XCTAssertEqual(CLICommand.parse([]), .failure(.empty))
        XCTAssertEqual(parse("bogus"), .failure(.unknown("bogus")))
        if case .failure(.usage(let text)) = parse("room") { XCTAssertTrue(text.contains("room")) } else { XCTFail("room alone needs a usage message") }
        if case .success = parse("float", "now") { XCTFail("extra arguments must be refused") }
        if case .success = parse("room", "1", "2") { XCTFail("extra arguments must be refused") }
    }

    func testCommandsAreCaseInsensitive() {
        XCTAssertEqual(parse("FOCUS", "LEFT"), .success(.focus(.left)))
    }

    func testHomeSetsARoomsDisplayOrClearsIt() {
        XCTAssertEqual(parse("home", "2", "1"), .success(.home(room: 2, display: 1)))
        XCTAssertEqual(parse("HOME", "3", "NONE"), .success(.home(room: 3, display: nil)))
    }

    func testHomeRefusesBadNumbersAndExtraWords() {
        for words in [["home"], ["home", "2"], ["home", "0", "1"], ["home", "10", "1"], ["home", "2", "0"], ["home", "2", "10"],
                      ["home", "2", "x"], ["home", "2", "1", "extra"]] {
            if case .success = CLICommand.parse(words) { XCTFail("\(words) must not parse") }
        }
    }

    func testHelpMentionsEveryCommand() {
        for word in ["room", "send", "focus", "move", "window", "pane", "move-to-pane", "float", "float-app", "rotate", "tiles",
                     "display", "undo-layout", "rescue", "start", "pause", "list", "status", "home", "room-to-display"] {
            XCTAssertTrue(CLICommand.helpText.contains(word), "help should mention \(word)")
        }
    }

    // MARK: output

    func testATableAlignsItsColumnsUnderTheHeader() {
        let rows = [["id": "1", "app": "Safari"], ["id": "22", "app": "Terminal"]]
        let lines = CLIFormat.table(rows, columns: ["id", "app"]).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("id"))
        // The second column starts at the same character offset in every line.
        let starts = [lines[0].range(of: "app"), lines[1].range(of: "Safari"), lines[2].range(of: "Terminal")]
            .compactMap { $0 }
            .enumerated()
            .map { lines[$0.offset].distance(from: lines[$0.offset].startIndex, to: $0.element.lowerBound) }
        XCTAssertEqual(starts.count, 3)
        XCTAssertEqual(Set(starts).count, 1)
    }

    func testAnEmptyTableSaysSo() {
        XCTAssertEqual(CLIFormat.table([], columns: ["id"]), "(none)")
    }

    func testJsonOutputIsAnArrayOfObjectsWithSortedKeys() throws {
        let text = CLIFormat.json([["b": "2", "a": "1"]])
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: String]])
        XCTAssertEqual(parsed, [["a": "1", "b": "2"]])
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "\"a\"")).lowerBound, try XCTUnwrap(text.range(of: "\"b\"")).lowerBound)
    }

    // MARK: the setting

    func testCommandLineControlIsOnByDefaultAndTheChoiceIsKept() throws {
        XCTAssertTrue(WorkspaceState().cliEnabled)
        var off = WorkspaceState()
        off.cliEnabled = false
        let kept = try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(off))
        XCTAssertFalse(kept.cliEnabled)
    }

    func testSettingsFromBeforeTheCommandLineLoadWithItOn() throws {
        var off = WorkspaceState()
        off.cliEnabled = false
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(off)) as? [String: Any])
        object["cliEnabled"] = nil
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(loaded.cliEnabled)
    }

    // MARK: the socket path

    func testTheSocketLivesInTheApplicationSupportFolder() {
        XCTAssertEqual(CLIPaths.socketPath(home: "/Users/sam", uid: 501), "/Users/sam/Library/Application Support/Tatami/tatami.sock")
    }

    func testALongHomeFolderFallsBackToAShortPrivatePath() {
        // A Unix socket path is limited to about 104 bytes.
        let long = "/Users/" + String(repeating: "a", count: 90)
        let path = CLIPaths.socketPath(home: long, uid: 501)
        XCTAssertEqual(path, "/tmp/tatami-501/tatami.sock")
        XCTAssertLessThanOrEqual(path.utf8.count, CLIPaths.maxSocketPathBytes)
    }

    func testControlCharactersAreStrippedFromCells() {
        let text = CLIFormat.table([["t": "a\u{1B}]0;pwned\u{07}b\nforged  row"]], columns: ["t"])
        XCTAssertFalse(text.unicodeScalars.contains { $0.value < 0x20 && $0 != "\n" })
        XCTAssertEqual(text.split(separator: "\n").count, 2)  // header and one row, no forged line
    }

    func testLongCellsAreShortenedAndNothingTrailsAtTheEnd() {
        let text = CLIFormat.table([["t": String(repeating: "x", count: 50_000), "u": ""]], columns: ["t", "u"])
        XCTAssertLessThan(text.count, 400)
        XCTAssertTrue(text.split(separator: "\n").allSatisfy { !$0.hasSuffix(" ") })
    }

    func testCleanReplacesLineBreaksAndDropsControlCharacters() {
        XCTAssertEqual(CLIFormat.clean("a\r\nb\u{1B}c"), "a  bc")
    }

    func testEmojiCellsAreNeverCutShort() {
        let text = CLIFormat.table([["t": "Inbox 🙂🙂 (3)"], ["t": "x"]], columns: ["t"])
        XCTAssertTrue(text.contains("Inbox 🙂🙂 (3)"))
    }
}

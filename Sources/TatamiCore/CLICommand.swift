import Foundation

public enum CLIListing: String, Equatable { case windows, rooms, displays }

/// What the `tatami` command can ask the app to do. Each action mirrors a keyboard shortcut that already exists.
public enum CLICommand: Equatable {
    case stage(Int), stageStep(Int), send(Int)
    case focus(Direction), move(Direction)
    case cycle(Int), pane(Int), movePane(Int), display(Int)
    case float, floatApp, rotate, tiles, undoLayout, rescue, start, pause
    case home(room: Int, display: Int?)
    case list(CLIListing, json: Bool)
    case status(json: Bool)
}

public enum CLIParseError: Error, Equatable {
    case empty, unknown(String), usage(String)
}

extension CLICommand {
    /// Command, its usage line and what it does. The parser's error messages and the help text both come from here.
    static let reference: [(name: String, usage: String, summary: String)] = [
        ("room", "room <1-9|next|prev>", "switch Room"),
        ("send", "send <1-9>", "send the focused window to a Room"),
        ("focus", "focus <left|right|up|down>", "focus the pane or window that way"),
        ("move", "move <left|right|up|down>", "move the window to the pane that way, or swap with the freeform window there"),
        ("window", "window <next|prev>", "focus the next or previous window across displays"),
        ("pane", "pane <1-9>", "focus a pane by the number on its tab bar"),
        ("move-to-pane", "move-to-pane <1-9>", "move the focused window into a pane by number"),
        ("float", "float", "float the focused window, or tile it if it floats"),
        ("float-app", "float-app", "the same for every window of the focused app"),
        ("rotate", "rotate", "turn the focused pane's split the other way"),
        ("tiles", "tiles", "switch the focused display between Tiles and Freeform"),
        ("display", "display <next|prev>", "send the focused window to another display"),
        ("undo-layout", "undo-layout", "undo the last layout change"),
        ("rescue", "rescue", "bring every hidden window back and pause"),
        ("start", "start", "start managing windows"),
        ("pause", "pause", "pause management and restore windows"),
        ("home", "home <1-9> <1-9|none>", "make a Room live on a display (numbers from list displays), or none"),
        ("list", "list <windows|rooms|displays> [--json]", "show what Tatami sees"),
        ("status", "status [--json]", "show whether Tatami is managing, and its version"),
    ]

    public static var helpText: String {
        let width = reference.map(\.usage.count).max() ?? 0
        let lines = reference.map { "  " + $0.usage.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + $0.summary }
        return (["Usage: tatami <command>", "", "Commands:"] + lines + ["", "The Tatami app must be running with command-line control on."]).joined(separator: "\n")
    }

    private static func usage(_ name: String) -> CLIParseError {
        .usage("Usage: " + (reference.first { $0.name == name }?.usage ?? name))
    }

    public static func parse(_ args: [String]) -> Result<CLICommand, CLIParseError> {
        guard let first = args.first?.lowercased() else { return .failure(.empty) }
        let name = first == "stage" ? "room" : first  // "stage" was the old word for a Room
        let rest = args.dropFirst().map { $0.lowercased() }
        let wrong = Result<CLICommand, CLIParseError>.failure(usage(name))

        func plain(_ command: CLICommand) -> Result<CLICommand, CLIParseError> { rest.isEmpty ? .success(command) : wrong }
        func number(_ make: (Int) -> CLICommand) -> Result<CLICommand, CLIParseError> {
            guard rest.count == 1, let n = Int(rest[0]), (1...9).contains(n) else { return wrong }
            return .success(make(n))
        }
        func step(_ make: (Int) -> CLICommand) -> Result<CLICommand, CLIParseError> {
            guard rest.count == 1, let sign = ["next": 1, "prev": -1][rest[0]] else { return wrong }
            return .success(make(sign))
        }
        func direction(_ make: (Direction) -> CLICommand) -> Result<CLICommand, CLIParseError> {
            guard rest.count == 1, let d = Direction(rawValue: rest[0]) else { return wrong }
            return .success(make(d))
        }
        /// An optional trailing `--json`, and nothing else.
        func jsonFlag(_ words: [String]) -> Bool? {
            if words.isEmpty { return false }
            return words == ["--json"] ? true : nil
        }

        switch name {
        case "room": return rest.first.map({ $0 == "next" || $0 == "prev" }) == true ? step(CLICommand.stageStep) : number(CLICommand.stage)
        case "send": return number(CLICommand.send)
        case "focus": return direction(CLICommand.focus)
        case "move": return direction(CLICommand.move)
        case "window": return step(CLICommand.cycle)
        case "pane": return number(CLICommand.pane)
        case "move-to-pane": return number(CLICommand.movePane)
        case "float": return plain(.float)
        case "float-app": return plain(.floatApp)
        case "rotate": return plain(.rotate)
        case "tiles": return plain(.tiles)
        case "display": return step(CLICommand.display)
        case "undo-layout": return plain(.undoLayout)
        case "rescue": return plain(.rescue)
        case "start": return plain(.start)
        case "pause": return plain(.pause)
        case "home":
            guard rest.count == 2, let room = Int(rest[0]), (1...9).contains(room) else { return wrong }
            if rest[1] == "none" { return .success(.home(room: room, display: nil)) }
            guard let display = Int(rest[1]), (1...9).contains(display) else { return wrong }
            return .success(.home(room: room, display: display))
        case "list":
            guard let what = rest.first.map({ $0 == "stages" ? "rooms" : $0 }).flatMap(CLIListing.init(rawValue:)), let json = jsonFlag(Array(rest.dropFirst())) else { return wrong }
            return .success(.list(what, json: json))
        case "status":
            guard let json = jsonFlag(rest) else { return wrong }
            return .success(.status(json: json))
        default: return .failure(.unknown(name))
        }
    }
}

public enum CLIFormat {
    static let maxCellWidth = 80

    /// Window titles come from other apps, so they are untrusted: line breaks and tabs become spaces and every other
    /// control character (escape sequences included) is dropped before anything reaches a terminal.
    public static func clean(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x2028, 0x2029: result.append(" ")
            case 0x00...0x1F, 0x7F...0x9F: continue
            default: result.append(scalar)
            }
        }
        return String(result)
    }

    /// Like `clean`, but keeps the line breaks of a multi-line reply.
    public static func cleanLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { clean(String($0)) }.joined(separator: "\n")
    }

    private static func cell(_ text: String) -> String {
        let cleaned = clean(text)
        return cleaned.count > maxCellWidth ? String(cleaned.prefix(maxCellWidth - 1)) + "…" : cleaned
    }

    /// Left aligned columns under a header; "(none)" when there is nothing to show.
    public static func table(_ rows: [[String: String]], columns: [String]) -> String {
        guard !rows.isEmpty else { return "(none)" }
        let cells = rows.map { row in columns.map { cell(row[$0] ?? "") } }
        let widths = columns.indices.map { index in max(columns[index].count, cells.map { $0[index].count }.max() ?? 0) }
        func line(_ values: [String]) -> String {
            // Pad by Character count: padding(toLength:) counts UTF-16 units and would cut emoji cells short.
            var text = zip(values, widths).map { $0 + String(repeating: " ", count: max(0, $1 - $0.count)) }.joined(separator: "  ")
            while text.hasSuffix(" ") { text.removeLast() }
            return text
        }
        return ([line(columns)] + cells.map(line)).joined(separator: "\n")
    }

    /// An array of objects with sorted keys, for scripts.
    public static func json(_ rows: [[String: String]]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

import Foundation

/// What the app knows about a connected display, for matching a Room's home preferences.
public struct DisplayDescriptor: Equatable {
    public var key: String
    public var name: String
    public var isBuiltIn: Bool
    public var isMain: Bool
    /// 1-based position in arrangement order (left to right, then top to bottom).
    public var position: Int

    public init(key: String, name: String, isBuiltIn: Bool, isMain: Bool, position: Int) {
        self.key = key; self.name = name; self.isBuiltIn = isBuiltIn; self.isMain = isMain; self.position = position
    }

    /// Descriptors with nothing but a key, for callers that only know which displays are connected.
    public static func keys(_ keys: [String]) -> [DisplayDescriptor] {
        keys.enumerated().map { DisplayDescriptor(key: $1, name: $1, isBuiltIn: false, isMain: false, position: $0 + 1) }
    }
}

/// One choice in a Room's ordered list of homes. The first one that matches a connected display wins, so a single setup
/// works at home, at work and on the laptop alone (AeroSpace's `workspace-to-monitor-force-assignment`).
public enum DisplayPreference: Codable, Equatable {
    /// A specific display, by hardware key.
    case key(String)
    /// A name pattern, ignoring case, found anywhere in the display's name.
    case pattern(String)
    case builtIn
    /// The main display, the one with the menu bar.
    case main
    /// Any display that is not the main one.
    case secondary
    /// The nth display in arrangement order.
    case position(Int)

    static let maxPatternLength = 200

    public func matches(_ display: DisplayDescriptor) -> Bool {
        switch self {
        case .key(let key): return display.key == key
        case .pattern(let text): return text.count <= Self.maxPatternLength && AeroNameMatcher.matches(text, name: display.name)
        case .builtIn: return display.isBuiltIn
        case .main: return display.isMain
        case .secondary: return !display.isMain
        case .position(let n): return display.position == n
        }
    }

    var isValid: Bool {
        switch self {
        case .key(let key): return !key.isEmpty && key.count <= 200
        case .pattern(let text): return !text.isEmpty && text.count <= Self.maxPatternLength
        case .position(let n): return (1...32).contains(n)
        default: return true
        }
    }
}

extension WorkspaceState {
    /// A Room has a home when a display is picked for it or it has a list of preferences.
    public func hasHome(_ room: UUID) -> Bool {
        guard let stage = stages.first(where: { $0.id == room }) else { return false }
        return stage.homeDisplay != nil || !stage.homeFallbacks.isEmpty
    }

    /// The ordered choices: the display picked in Room Settings first, then the list.
    func homeChoices(of room: UUID) -> [DisplayPreference] {
        guard let stage = stages.first(where: { $0.id == room }) else { return [] }
        return (stage.homeDisplay.map { [DisplayPreference.key($0)] } ?? []) + stage.homeFallbacks
    }

    /// Sets the ordered list of homes after the picked display. Turns on per-display Rooms, which homes need.
    /// False for an unknown Room, or when none of the choices was usable (an over-long pattern, say).
    @discardableResult public mutating func setHomeFallbacks(_ preferences: [DisplayPreference], for room: UUID, enablingPerDisplayRooms: Bool = true) -> Bool {
        guard let index = stages.firstIndex(where: { $0.id == room }) else { return false }
        let usable = Array(preferences.filter(\.isValid).prefix(8))
        guard usable.count == preferences.prefix(8).count || preferences.isEmpty else { return false }
        stages[index].homeFallbacks = usable
        if !usable.isEmpty, enablingPerDisplayRooms, !perDisplayRooms { setPerDisplayRooms(true) }
        return true
    }

    /// The display the Room lives on right now: its first choice that matches a connected display. Nil when none does, or
    /// per-display Rooms is off.
    public func effectiveHome(of room: UUID, displays: [DisplayDescriptor]) -> String? {
        guard perDisplayRooms else { return nil }
        let ordered = displays.sorted { $0.position < $1.position }  // the same answer whatever order the system lists them in
        for choice in homeChoices(of: room) {
            if let display = ordered.first(where: { choice.matches($0) }) { return display.key }
        }
        return nil
    }

    /// The Room that lives on a display: the first, in list order, whose home resolves to it.
    public func homeRoom(of display: String, displays: [DisplayDescriptor]) -> UUID? {
        stages.first { effectiveHome(of: $0.id, displays: displays) == display }?.id
    }

    public func homeIsShowing(_ room: UUID, displays: [DisplayDescriptor]) -> Bool {
        guard let home = effectiveHome(of: room, displays: displays) else { return false }
        return activeRoomID(on: home) == room
    }

    public func routedTarget(bundleID: String, title: String, displays: [DisplayDescriptor]) -> RoutedTarget? {
        guard let room = destination(bundleID: bundleID, title: title) else { return nil }
        return RoutedTarget(room: room, display: effectiveHome(of: room, displays: displays))
    }

    public func homeToMoveTo(room: UUID, currentDisplay: String?, displays: [DisplayDescriptor]) -> String? {
        guard let home = effectiveHome(of: room, displays: displays), home != currentDisplay else { return nil }
        return home
    }

    /// Puts each connected display on its home Room, unless it already has a choice of its own (you switched it).
    public mutating func applyHomes(displays: [DisplayDescriptor]) {
        guard perDisplayRooms else { return }
        for display in displays {
            if let own = displayRooms[display.key], stages.contains(where: { $0.id == own }) { continue }  // a live choice of its own
            if let home = homeRoom(of: display.key, displays: displays) { displayRooms[display.key] = home }
        }
    }
}

extension AeroSpaceConfig {
    /// `[workspace-to-monitor-force-assignment]`: workspace name to an ordered list of monitor choices. Keywords ignore case:
    /// main, secondary, built-in; an unquoted number is a position; anything else is a name pattern.
    public static func parseMonitorAssignments(_ text: String) -> [String: [DisplayPreference]] {
        var result: [String: [DisplayPreference]] = [:]
        var inSection = false
        var lines = text.components(separatedBy: .newlines)[...]
        while let raw = lines.popFirst() {
            let line = stripHash(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[") && !line.contains("=") {
                inSection = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces) == "workspace-to-monitor-force-assignment"
                continue
            }
            guard inSection, let equals = line.firstIndex(of: "=") else { continue }
            let workspace = line[..<equals].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            var extra = 0
            while value.hasPrefix("["), !closesList(value), extra < 100, let next = lines.first {
                let trimmed = stripHash(next).trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && !trimmed.contains("=") && !trimmed.contains("'") { break }  // the next table
                lines.removeFirst(); value += " " + trimmed; extra += 1
            }
            let preferences = items(in: value).compactMap(preference(from:))
            if !workspace.isEmpty, !preferences.isEmpty { result[workspace] = preferences }
        }
        return result
    }

    private struct Item { var text: String; var quoted: Bool }

    private static func preference(from item: Item) -> DisplayPreference? {
        if !item.quoted {
            if let n = Int(item.text) { return (1...32).contains(n) ? .position(n) : nil }
            switch item.text.lowercased() {
            case "main": return .main
            case "secondary": return .secondary
            case "built-in", "builtin": return .builtIn
            default: break
            }
        }
        switch item.text.lowercased() {
        case "main" where item.quoted: return .main
        case "secondary" where item.quoted: return .secondary
        case "built-in" where item.quoted, "builtin" where item.quoted: return .builtIn
        default: return item.text.isEmpty ? nil : .pattern(item.text)
        }
    }

    /// Whether a bracketed list has its closing bracket, ignoring brackets inside quotes.
    private static func closesList(_ value: String) -> Bool {
        var quote: Character?
        for c in value {
            if let open = quote { if c == open { quote = nil } } else if c == "'" || c == "\"" { quote = c } else if c == "]" { return true }
        }
        return false
    }

    /// The elements of `'a'`, `"a"`, `3`, or `['a', 'b', 3]`.
    private static func items(in value: String) -> [Item] {
        var result: [Item] = [], buffer = "", quote: Character?, wasQuoted = false, depth = 0
        func flush() {
            let text = wasQuoted ? buffer : buffer.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { result.append(Item(text: text, quoted: wasQuoted)) }
            buffer = ""; wasQuoted = false
        }
        for c in value {
            if let open = quote { if c == open { quote = nil } else { buffer.append(c) } }
            else if c == "'" || c == "\"" { quote = c; wasQuoted = true; buffer = "" }  // whatever came before the opening quote is spacing
            else if c == "[" && depth == 0 { depth = 1 }
            else if c == "," || c == "]" { flush(); if c == "]" { break } }
            else if !wasQuoted { buffer.append(c) }  // spacing after a closing quote is not part of the name
        }
        flush()
        return result
    }

    private static func stripHash(_ line: String) -> String {
        var quote: Character?
        for index in line.indices {
            let c = line[index]
            if let open = quote { if c == open { quote = nil } } else if c == "'" || c == "\"" { quote = c } else if c == "#" { return String(line[..<index]) }
        }
        return line
    }
}

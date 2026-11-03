import Foundation

/// A display setup is the whole set of connected displays, such as laptop + portable + room monitor. Naming the set, not one
/// display, keeps places that share a monitor (a portable one used at home and at work) from sharing a layout.
public enum DisplaySetupKey {
    /// Order does not matter and a repeated key counts once. Nil when there are no displays.
    public static func make(_ displayKeys: [String]) -> String? {
        let unique = Array(Set(displayKeys)).sorted()
        return unique.isEmpty ? nil : unique.joined(separator: "|")
    }
}

/// What to do when the displays change to a setup that has a saved layout.
public enum DisplayChangePolicy: String, Codable, CaseIterable {
    case restore, ask, nothing
}

public enum DisplayChangeAction: Equatable {
    case restore
    case ask
    /// Leave the windows alone and keep saving the layout for this setup.
    case track
}

public enum DisplaySetupRules {
    /// A setup that has never been seen is only tracked: a layout from other monitors could put windows off screen.
    public static func action(policy: DisplayChangePolicy, known: Bool) -> DisplayChangeAction {
        guard known else { return .track }
        switch policy {
        case .restore: return .restore
        case .ask: return .ask
        case .nothing: return .track
        }
    }
}

public struct DisplaySetup: Codable {
    public var key: String
    public var displayKeys: [String]
    public var displayNames: [String]
    /// A name you gave it ("Home"), or nil for the automatic one.
    public var name: String?
    public var lastUsed: Date
    public var checkpoint: Checkpoint

    /// The name you gave it, else its displays' names.
    public var title: String {
        if let name, !name.isEmpty { return name }
        let names = displayNames.filter { !$0.isEmpty }
        return names.isEmpty ? "Display setup" : names.joined(separator: " + ")
    }
}

/// The last few display setups with the layout each had. Eight, least recently used first to go.
public struct DisplaySetupStore: Codable {
    public static let maxSetups = 8
    static let maxWindows = 500
    static let maxNameLength = 60
    /// Window titles can hold document and page names, so they are kept short.
    static let maxTitleLength = 200

    public private(set) var setups: [DisplaySetup] = []

    public init() {}

    /// Reads leniently: one setup that cannot be read, is oversized or repeats a key is dropped, not the whole file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let all = (try c.decodeIfPresent([Lossy<DisplaySetup>].self, forKey: .setups) ?? []).compactMap(\.value)
        var byKey: [String: DisplaySetup] = [:]
        for var setup in all where !setup.checkpoint.windows.isEmpty && setup.checkpoint.windows.count <= Self.maxWindows {
            setup.name = setup.name.map { String($0.prefix(Self.maxNameLength)) }
            setup.displayNames = setup.displayNames.prefix(16).map { String($0.prefix(80)) }
            if let existing = byKey[setup.key], existing.lastUsed >= setup.lastUsed { continue }
            byKey[setup.key] = setup
        }
        setups = all.compactMap { byKey[$0.key] }.reduce(into: [DisplaySetup]()) { result, setup in
            if !result.contains(where: { $0.key == setup.key }) { result.append(setup) }
        }
        trim(keeping: nil)
    }

    /// The setup for exactly this set of displays.
    public func setup(for displayKeys: [String]) -> DisplaySetup? {
        guard let key = DisplaySetupKey.make(displayKeys) else { return nil }
        return setups.first { $0.key == key }
    }

    /// Saves the layout for a setup, replacing the old one and keeping its name. An empty or oversized checkpoint is refused
    /// so a bad scan never overwrites a good layout.
    @discardableResult public mutating func save(_ checkpoint: Checkpoint, displayKeys: [String], displayNames: [String], at date: Date) -> Bool {
        guard let key = DisplaySetupKey.make(displayKeys), !checkpoint.windows.isEmpty, checkpoint.windows.count <= Self.maxWindows else { return false }
        var checkpoint = checkpoint
        for index in checkpoint.windows.indices { checkpoint.windows[index].title = String(checkpoint.windows[index].title.prefix(Self.maxTitleLength)) }
        if let index = setups.firstIndex(where: { $0.key == key }) {
            setups[index].checkpoint = checkpoint
            setups[index].lastUsed = date
            if !displayNames.isEmpty { setups[index].displayNames = displayNames }
        } else {
            setups.append(DisplaySetup(key: key, displayKeys: Array(Set(displayKeys)).sorted(), displayNames: displayNames, name: nil, lastUsed: date, checkpoint: checkpoint))
        }
        trim(keeping: key)
        return true
    }

    /// Marks a setup as just used, so it is the last to be dropped.
    public mutating func touch(_ key: String, at date: Date) {
        if let index = setups.firstIndex(where: { $0.key == key }) { setups[index].lastUsed = date }
    }

    /// A name you choose; an empty one goes back to the automatic name. False for an unknown setup or a name over 60 characters.
    @discardableResult public mutating func rename(_ key: String, to name: String?) -> Bool {
        guard let index = setups.firstIndex(where: { $0.key == key }) else { return false }
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= Self.maxNameLength else { return false }
        setups[index].name = trimmed.isEmpty ? nil : trimmed
        return true
    }

    public mutating func remove(_ key: String) { setups.removeAll { $0.key == key } }

    /// Forgets setups not used for a long time.
    public mutating func prune(olderThan interval: TimeInterval, now: Date) {
        setups.removeAll { now.timeIntervalSince($0.lastUsed) > interval }
    }

    /// Keeps the most recently used setups; `keeping` (the one just saved) always stays, and a tie goes to the newer entry.
    private mutating func trim(keeping key: String?) {
        guard setups.count > Self.maxSetups else { return }
        let ranked = setups.enumerated().sorted { a, b in
            if (a.element.key == key) != (b.element.key == key) { return a.element.key == key }
            if a.element.lastUsed != b.element.lastUsed { return a.element.lastUsed > b.element.lastUsed }
            return a.offset > b.offset
        }
        let keepers = Set(ranked.prefix(Self.maxSetups).map(\.offset))
        setups = setups.enumerated().filter { keepers.contains($0.offset) }.map(\.element)
    }

    private enum CodingKeys: String, CodingKey { case setups }
}

/// Decodes to nil instead of throwing, so one bad element does not fail the whole list.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

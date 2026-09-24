import Foundation
import CoreGraphics

public struct Stage: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public init(id: UUID = UUID(), name: String, symbol: String = "square.stack.3d.up") {
        self.id = id; self.name = name; self.symbol = symbol
    }
}

public struct RoutingRule: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var bundleID: String
    public var appName: String
    public var titleContains: String
    public var stageID: UUID
    public var enabled: Bool
    public init(bundleID: String, appName: String, titleContains: String = "", stageID: UUID, enabled: Bool = true) {
        self.bundleID = bundleID; self.appName = appName; self.titleContains = titleContains
        self.stageID = stageID; self.enabled = enabled
    }
}

public struct Rect: Codable, Equatable {
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(_ rect: CGRect) { x = rect.minX; y = rect.minY; width = rect.width; height = rect.height }
    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

public struct WindowSnapshot: Codable, Identifiable {
    public var id: UUID = UUID()
    public var bundleID: String
    public var title: String
    public var occurrence: Int
    public var stageID: UUID
    public var frame: Rect
    public init(bundleID: String, title: String, occurrence: Int, stageID: UUID, frame: CGRect) {
        self.bundleID = bundleID; self.title = title; self.occurrence = occurrence
        self.stageID = stageID; self.frame = Rect(frame)
    }
}

public struct SavedWorkspace: Codable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var date: Date = Date()
    public var stages: [Stage]
    public var activeStageID: UUID
    public var windows: [WindowSnapshot]
    public init(name: String, stages: [Stage], activeStageID: UUID, windows: [WindowSnapshot]) {
        self.name = name; self.stages = stages; self.activeStageID = activeStageID; self.windows = windows
    }
}

public struct WorkspaceState: Codable {
    public var version = 1
    public var stages: [Stage]
    public var activeStageID: UUID
    public var saved: [SavedWorkspace] = []
    public var rules: [RoutingRule] = []
    public var excludedBundleIDs: [String] = []
    public var followSentWindow = false
    /// Focusing a window from another Stage switches to it (M1 decision 11).
    public var followActivatedWindows = true
    public var shortcutPreset: ShortcutPreset = .standard
    public var gap: Double = 12
    public var ai: AIConfig?

    public init() {
        stages = [Stage(name: "Work", symbol: "square.grid.2x2"), Stage(name: "Comms", symbol: "bubble.left.and.bubble.right"), Stage(name: "Browse", symbol: "globe")]
        activeStageID = stages[0].id
    }

    private enum CodingKeys: String, CodingKey {
        case version, stages, activeStageID, saved, rules, excludedBundleIDs, followSentWindow, followActivatedWindows, shortcutPreset, gap, ai
    }

    // Missing keys fall back to defaults so older files keep loading. Legacy `europeanShortcuts` is ignored: every file migrates to `.standard`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WorkspaceState()
        version = try c.decode(Int.self, forKey: .version)
        stages = try c.decode([Stage].self, forKey: .stages)
        activeStageID = try c.decode(UUID.self, forKey: .activeStageID)
        saved = try c.decodeIfPresent([SavedWorkspace].self, forKey: .saved) ?? defaults.saved
        rules = try c.decodeIfPresent([RoutingRule].self, forKey: .rules) ?? defaults.rules
        excludedBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? defaults.excludedBundleIDs
        followSentWindow = try c.decodeIfPresent(Bool.self, forKey: .followSentWindow) ?? defaults.followSentWindow
        followActivatedWindows = try c.decodeIfPresent(Bool.self, forKey: .followActivatedWindows) ?? defaults.followActivatedWindows
        shortcutPreset = try c.decodeIfPresent(ShortcutPreset.self, forKey: .shortcutPreset) ?? defaults.shortcutPreset
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? defaults.gap
        ai = try c.decodeIfPresent(AIConfig.self, forKey: .ai)
    }

    public var activeStage: Stage { stages.first(where: { $0.id == activeStageID }) ?? stages[0] }

    public mutating func validate() throws {
        guard version == 1 else { throw ValidationError.unsupportedVersion }
        guard !stages.isEmpty, stages.count <= 9, Set(stages.map(\.id)).count == stages.count,
              stages.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 60 }),
              gap.isFinite, (0...40).contains(gap), saved.count <= 100,
              rules.count <= 500, ai?.isValid ?? true else { throw ValidationError.invalidState }
        guard stages.contains(where: { $0.id == activeStageID }) else { throw ValidationError.invalidState }
        for workspace in saved {
            guard !workspace.stages.isEmpty, workspace.stages.count <= 9,
                  Set(workspace.stages.map(\.id)).count == workspace.stages.count,
                  workspace.stages.contains(where: { $0.id == workspace.activeStageID }),
                  workspace.windows.allSatisfy({ window in
                      let r = window.frame
                      return r.x.isFinite && r.y.isFinite && r.width.isFinite && r.height.isFinite && r.width > 0 && r.height > 0 && workspace.stages.contains(where: { $0.id == window.stageID })
                  }) else { throw ValidationError.invalidState }
        }
    }

    public func destination(bundleID: String, title: String) -> UUID? {
        guard !excludedBundleIDs.contains(bundleID) else { return nil }
        return rules.first { rule in
            rule.enabled && rule.bundleID == bundleID &&
            (rule.titleContains.isEmpty || title.localizedCaseInsensitiveContains(rule.titleContains)) &&
            stages.contains(where: { $0.id == rule.stageID })
        }?.stageID
    }

    @discardableResult public mutating func addStage(name: String) -> Stage? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stages.count < 9, !name.isEmpty, name.count <= 60 else { return nil }
        let stage = Stage(name: name); stages.append(stage); return stage
    }

    public mutating func removeStage(_ id: UUID) -> UUID? {
        guard stages.count > 1, stages.contains(where: { $0.id == id }) else { return nil }
        stages.removeAll { $0.id == id }
        if activeStageID == id { activeStageID = stages[0].id }
        return activeStageID
    }
}

/// Non-secret AI settings, keyed by provider preset ID. API keys live only in the Keychain.
public struct AIConfig: Codable, Equatable {
    public var presetID = "anthropic"
    public var customBaseURL = ""
    public var models: [String: String] = [:]
    /// Missing means true: titles are sent unless the user opts out for that provider.
    public var sendTitles: [String: Bool] = [:]
    public var disclosed: [String] = []
    public init() {}

    public var isValid: Bool {
        presetID.count <= 40 && models.count <= 20 && models.values.allSatisfy { $0.count <= 200 } && disclosed.count <= 20 &&
            (customBaseURL.isEmpty || Self.acceptableBaseURL(customBaseURL))
    }

    /// HTTPS anywhere, plain HTTP only for this Mac, so keys never cross the network unencrypted.
    public static func acceptableBaseURL(_ text: String) -> Bool {
        guard text.count <= 500, let url = URL(string: text), let host = url.host?.lowercased() else { return false }
        return url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host))
    }
}

/// `standard` keeps plain Option free for typing and word navigation. `classic` uses Option alone for Stage actions.
public enum ShortcutPreset: String, Codable, CaseIterable {
    case standard, classic
    public var stageModifiers: String { self == .standard ? "⌃⌥" : "⌥" }
    public var navigationModifiers: String { self == .standard ? "⌃⌥⌘" : "⌥" }
}

public enum ValidationError: LocalizedError {
    case unsupportedVersion, invalidState
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This backup uses a version Tatami does not support."
        case .invalidState: "The workspace file contains invalid stages, layouts, or settings. Nothing was imported."
        }
    }
}

public enum SnapZone: String, CaseIterable, Identifiable {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, centerTwoThirds, rightTwoThirds, center, maximize
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .left: "Left half"; case .right: "Right half"; case .top: "Top half"; case .bottom: "Bottom half"
        case .topLeft: "Top left"; case .topRight: "Top right"; case .bottomLeft: "Bottom left"; case .bottomRight: "Bottom right"
        case .leftThird: "Left third"; case .centerThird: "Center third"; case .rightThird: "Right third"
        case .leftTwoThirds: "Left two thirds"; case .centerTwoThirds: "Center two thirds"; case .rightTwoThirds: "Right two thirds"
        case .center: "Center"; case .maximize: "Maximize"
        }
    }
    public var unit: CGRect {
        switch self {
        case .left: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .right: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .top: CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottom: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .leftThird: CGRect(x: 0, y: 0, width: 1.0/3, height: 1)
        case .centerThird: CGRect(x: 1.0/3, y: 0, width: 1.0/3, height: 1)
        case .rightThird: CGRect(x: 2.0/3, y: 0, width: 1.0/3, height: 1)
        case .leftTwoThirds: CGRect(x: 0, y: 0, width: 2.0/3, height: 1)
        case .centerTwoThirds: CGRect(x: 1.0/6, y: 0, width: 2.0/3, height: 1)
        case .rightTwoThirds: CGRect(x: 1.0/3, y: 0, width: 2.0/3, height: 1)
        case .center: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        case .maximize: CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }
    public func frame(in area: CGRect, gap: Double = 0) -> CGRect {
        let r = unit
        let raw = CGRect(x: area.minX + r.minX * area.width, y: area.minY + r.minY * area.height, width: r.width * area.width, height: r.height * area.height)
        let inset = min(max(0, gap / 2), min(raw.width, raw.height) / 4)
        return raw.insetBy(dx: inset, dy: inset).integral
    }
}

public enum Geometry {
    /// AX uses a top-left desktop origin. AppKit uses a bottom-left origin.
    public static func accessibilityFrame(_ frame: CGRect, primaryHeight: Double) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
    public static func visibleFrame(_ frame: CGRect, in area: CGRect) -> CGRect {
        let width = min(max(frame.width, 100), area.width)
        let height = min(max(frame.height, 80), area.height)
        return CGRect(x: min(max(frame.minX, area.minX), area.maxX - width),
                      y: min(max(frame.minY, area.minY), area.maxY - height), width: width, height: height)
    }
    public static func grid(count: Int, area: CGRect, gap: Double) -> [CGRect] {
        guard count > 0 else { return [] }
        let columns = Int(ceil(sqrt(Double(count) * area.width / max(area.height, 1))))
        let cols = max(1, min(count, columns))
        let rows = Int(ceil(Double(count) / Double(cols)))
        return (0..<count).map { index in
            let row = index / cols, column = index % cols
            let itemsInRow = min(cols, count - row * cols)
            let width = area.width / Double(itemsInRow), height = area.height / Double(rows)
            return CGRect(x: area.minX + Double(column) * width, y: area.minY + Double(row) * height, width: width, height: height).insetBy(dx: gap/2, dy: gap/2).integral
        }
    }
}

import Foundation

extension WorkspaceState {
    /// Merge All (M2 decision 8): the first Stage keeps every window; the rest are removed.
    @discardableResult public mutating func mergeAll() -> UUID {
        let first = stages[0]
        stages = [first]
        activeStageID = first.id
        displayRooms = [:]
        return first.id
    }

    /// The Stage `offset` positions from the active one, wrapping around.
    public func stageID(offset: Int) -> UUID {
        let index = stages.firstIndex { $0.id == activeStageID } ?? 0
        let count = stages.count
        return stages[((index + offset) % count + count) % count].id
    }

    public func nextStageName() -> String {
        var number = stages.count + 1
        while stages.contains(where: { $0.name.caseInsensitiveCompare("Room \(number)") == .orderedSame }) { number += 1 }
        return "Room \(number)"
    }
}

/// Offline first-run sorting (M2 decision 7).
public enum StageCategory: CaseIterable {
    case work, comms, browse

    public var stageName: String {
        switch self { case .work: "Work"; case .comms: "Comms"; case .browse: "Browse" }
    }

    static let commsApps: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.apple.mail", "com.apple.MobileSMS", "com.apple.FaceTime", "com.microsoft.teams2", "com.microsoft.teams",
        "us.zoom.xos", "com.hnc.Discord", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "com.readdle.smartemail-Mac", "com.microsoft.Outlook",
        "com.facebook.archon", "org.whispersystems.signal-desktop", "com.superhuman.electron", "com.spark.desktop",
    ]
    static let browseApps: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox", "com.microsoft.edgemac",
        "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "app.zen-browser.zen", "com.kagi.kagimacOS",
    ]

    public static func classify(_ bundleID: String) -> StageCategory {
        commsApps.contains(bundleID) ? .comms : browseApps.contains(bundleID) ? .browse : .work
    }
}

public struct SortPlan: Equatable {
    /// Stages to create, in category order.
    public var create: [String]
    /// Destination Stage name for each input window, index-aligned.
    public var assignments: [String]

    /// Reuses Stages whose names match a category (case-insensitive); falls back to the first Stage at the limit.
    public static func make(bundleIDs: [String], stageNames: [String], stageLimit: Int) -> SortPlan {
        let categories = bundleIDs.map(StageCategory.classify)
        var names = stageNames, create: [String] = []
        var destination: [StageCategory: String] = [:]
        for category in StageCategory.allCases where categories.contains(category) {
            if let existing = names.first(where: { $0.caseInsensitiveCompare(category.stageName) == .orderedSame }) {
                destination[category] = existing
            } else if names.count < stageLimit {
                names.append(category.stageName); create.append(category.stageName); destination[category] = category.stageName
            } else {
                destination[category] = names[0]
            }
        }
        return SortPlan(create: create, assignments: categories.map { destination[$0]! })
    }
}

/// Turns a stream of scroll deltas into at most one Stage switch per gesture (M2 decision 5).
public struct ScrollAccumulator {
    public let threshold: Double
    public let cooldown: TimeInterval
    private var total = 0.0
    private var lastFire = -Double.infinity

    public init(threshold: Double, cooldown: TimeInterval) { self.threshold = threshold; self.cooldown = cooldown }

    /// +1 next Stage (scrolling down), -1 previous, 0 nothing yet.
    public mutating func add(delta: Double, at time: TimeInterval) -> Int {
        guard time - lastFire >= cooldown else { total = 0; return 0 }  // momentum from the gesture that already fired
        if total != 0 && (total > 0) != (delta > 0) { total = 0 }
        total += delta
        guard abs(total) >= threshold else { return 0 }
        defer { total = 0; lastFire = time }
        return total < 0 ? 1 : -1
    }
}

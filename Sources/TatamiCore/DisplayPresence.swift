import Foundation

/// Tells a display that was really unplugged from one that vanished for a moment. Waking from sleep, a flaky cable or a
/// monitor switching inputs can drop a display from the list for a few seconds; moving windows and merging layouts then
/// would scramble a desk that was fine. A display counts as gone only after it has been missing for the whole `grace`.
public struct DisplayPresence {
    public struct Change: Equatable {
        /// Displays confirmed unplugged (missing for the whole grace period), reported once.
        public var gone: Set<String> = []
        /// Displays that are new, or that came back after being reported gone.
        public var returned: Set<String> = []
    }

    public let grace: TimeInterval
    /// Displays we consider connected (they may be missing right now, until the grace ends).
    private var known: Set<String> = []
    private var missingSince: [String: TimeInterval] = [:]

    public init(grace: TimeInterval = 8) { self.grace = grace }

    /// Displays missing right now but not yet confirmed gone.
    public var pendingMissing: Set<String> { Set(missingSince.keys) }

    /// Feed the current display list with a monotonic time in seconds.
    public mutating func update(current: Set<String>, now: TimeInterval) -> Change {
        var change = Change()
        for key in current {
            missingSince[key] = nil
            if known.insert(key).inserted { change.returned.insert(key) }
        }
        for key in known where !current.contains(key) {
            if missingSince[key] == nil { missingSince[key] = now }
            if let since = missingSince[key], now - since >= grace {
                change.gone.insert(key)
                known.remove(key)
                missingSince[key] = nil
            }
        }
        return change
    }

    /// Seconds until a pending display would be confirmed gone, or nil when none is pending. Zero when already due.
    public func nextCheck(now: TimeInterval) -> TimeInterval? {
        missingSince.values.map { max(0, $0 + grace - now) }.min()
    }
}

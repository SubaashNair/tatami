import Foundation

/// Per-display Rooms: with the setting on, each display shows its own Room and switches on its own. With it off (the
/// default) one Room is active everywhere, exactly as before. `activeStageID` stays the Room last switched to, and is
/// what any display without its own entry follows.
extension WorkspaceState {
    /// The Room showing on a display. Unknown displays, and entries pointing at a removed Room, follow `activeStageID`.
    public func activeRoomID(on display: String?) -> UUID {
        guard perDisplayRooms, let display, let own = displayRooms[display], stages.contains(where: { $0.id == own }) else { return activeStageID }
        return own
    }

    /// Switches the Room on one display, or everywhere while the setting is off. False for a Room that does not exist.
    /// `displays` are all the connected displays: each one keeps the Room it shows now, so switching one never moves another.
    /// While per-display Rooms is on a display is required: without one the switch is refused rather than moving every display.
    @discardableResult public mutating func switchRoom(_ id: UUID, on display: String?, displays: [String]) -> Bool {
        guard stages.contains(where: { $0.id == id }) else { return false }
        if perDisplayRooms {
            guard let display else { return false }
            for other in displays where other != display { displayRooms[other] = activeRoomID(on: other) }
            displayRooms[display] = id
        } else {
            displayRooms = [:]
        }
        activeStageID = id
        return true
    }

    /// Puts every display on one Room, the way a global switch always did.
    public mutating func switchRoomEverywhere(_ id: UUID) {
        guard stages.contains(where: { $0.id == id }) else { return }
        activeStageID = id
        displayRooms = [:]
    }

    /// Whether a Room is the one showing on a display.
    public func isActiveRoom(_ room: UUID, on display: String?) -> Bool { room == activeRoomID(on: display) }

    /// A window is visible when its Room is the one showing on the display it sits on. Always-visible apps are never hidden.
    public func isVisible(room: UUID, bundleID: String, on display: String?) -> Bool {
        excludedBundleIDs.contains(bundleID) || room == activeRoomID(on: display)
    }

    /// A window sent to a display joins the Room showing there, so it never disappears on arrival.
    public func roomForWindowSent(to display: String?) -> UUID { activeRoomID(on: display) }

    /// The Room `offset` steps from the one showing on a display, wrapping around.
    public func stageID(offset: Int, on display: String?) -> UUID {
        let current = activeRoomID(on: display)
        let index = stages.firstIndex { $0.id == current } ?? 0
        let count = stages.count
        return stages[((index + offset) % count + count) % count].id
    }

    /// Turning it on starts every display on the current Room; turning it off collapses them onto the last switched one.
    public mutating func setPerDisplayRooms(_ on: Bool) {
        guard on != perDisplayRooms else { return }  // asking for what is already set must not reset the displays
        perDisplayRooms = on
        displayRooms = [:]
    }
}

/// Remembers which display each window was last seen on, so a window the user drags to another display can be told
/// apart from one that has not moved.
public struct WindowDisplayTracker {
    private var known: [UUID: String] = [:]

    public init() {}

    /// Records where a window is now. Returns the display it came from when it moved to a different one, otherwise nil.
    public mutating func update(window: UUID, display: String?) -> String? {
        guard let display else { return nil }
        defer { known[window] = display }
        guard let previous = known[window], previous != display else { return nil }
        return previous
    }

    /// Drops windows that no longer exist.
    public mutating func keepOnly(_ ids: Set<UUID>) { known = known.filter { ids.contains($0.key) } }
}

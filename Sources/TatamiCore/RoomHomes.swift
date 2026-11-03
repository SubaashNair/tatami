import Foundation

/// Where a window of a routed app should go: its Room, and the display that Room lives on (when it has one that is connected).
public struct RoutedTarget: Equatable {
    public var room: UUID
    public var display: String?
    public init(room: UUID, display: String?) { self.room = room; self.display = display }
}

/// Room homes: a Room can live on a display, so "coding apps on display 1, chat on display 2" is a setting. Homes work
/// only with per-display Rooms on, which setting one turns on. Pure rules; the app moves the windows.
extension WorkspaceState {
    /// How new windows open in a Room: its own choice; tabs for a Room that lives on a display; else the desk-wide setting.
    /// The tabs default is derived, not stored, so removing a home goes back to the desk-wide setting.
    public func placement(forRoom room: UUID) -> NewWindowPlacement {
        guard let stage = stages.first(where: { $0.id == room }) else { return newWindowPlacement }
        return stage.placement ?? (hasHome(room) ? .active : newWindowPlacement)
    }

    public mutating func setPlacement(_ placement: NewWindowPlacement?, for room: UUID) {
        guard let index = stages.firstIndex(where: { $0.id == room }) else { return }
        stages[index].placement = placement
    }

    public func homeDisplay(of room: UUID) -> String? { stages.first(where: { $0.id == room })?.homeDisplay }

    /// The Room that lives on a display. With several, the first in the list.
    public func homeRoom(of display: String) -> UUID? { stages.first(where: { $0.homeDisplay == display })?.id }

    /// Gives a Room a home display (nil removes it). A home turns per-display Rooms on and makes that display show the Room
    /// now. `displays` must be every connected display, so the others keep what they show. False for a Room that does not exist.
    @discardableResult public mutating func setHome(_ display: String?, for room: UUID, displays: [String]) -> Bool {
        guard let index = stages.firstIndex(where: { $0.id == room }) else { return false }
        stages[index].homeDisplay = display
        guard let display else { stages[index].homeFallbacks = []; return true }  // none means no home at all
        if !perDisplayRooms { setPerDisplayRooms(true) }
        switchRoom(room, on: display, displays: displays)
        return true
    }

    /// The home display of a Room, only when homes apply: the mode is on and that display is connected.
    public func effectiveHome(of room: UUID, connected: [String]) -> String? {
        effectiveHome(of: room, displays: DisplayDescriptor.keys(connected))
    }

    /// Whether the Room's home display is showing it right now. A routed window still goes home when it is not, and waits
    /// there, hidden, until that display is switched to the Room, as an inactive Room's windows always do.
    public func homeIsShowing(_ room: UUID, connected: [String]) -> Bool {
        homeIsShowing(room, displays: DisplayDescriptor.keys(connected))
    }

    /// Where a window of an app with a routing rule belongs. Nil when no rule matches, or the app is always visible.
    public func routedTarget(bundleID: String, title: String, connected: [String]) -> RoutedTarget? {
        routedTarget(bundleID: bundleID, title: title, displays: DisplayDescriptor.keys(connected))
    }

    /// The display a window should be moved to, when its Room lives elsewhere. Nil when it is already home or has no home.
    public func homeToMoveTo(room: UUID, currentDisplay: String?, connected: [String]) -> String? {
        homeToMoveTo(room: room, currentDisplay: currentDisplay, displays: DisplayDescriptor.keys(connected))
    }

    /// Puts each connected display on its home Room, unless it already has a choice of its own (you switched it).
    public mutating func applyHomes(connected: [String]) {
        applyHomes(displays: DisplayDescriptor.keys(connected))
    }
}

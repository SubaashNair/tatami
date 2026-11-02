import AppKit
import TatamiCore

/// Room homes wiring (rules live in TatamiCore/RoomHomes.swift). A Room can live on a display: windows of apps routed to
/// it open there, as tabs by default, and that display keeps showing the Room.
extension AppModel {
    /// Displays in arrangement order from the live list (the published one lags a scan behind), numbered as in `tatami list displays`.
    private var liveOrderedDisplays: [DisplayInfo] {
        DisplayOrder.ordered(service.displays.map { ($0.id, $0.fullFrame) }).compactMap { id in service.displays.first { $0.id == id } }
    }

    /// `tatami home <room> <display|none>`. Numbers match `tatami list rooms` and `tatami list displays`.
    func setRoomHome(room roomNumber: Int, display displayNumber: Int?) -> CLIResponse {
        guard state.stages.indices.contains(roomNumber - 1) else { return .failure("There is no Room \(roomNumber).") }
        let room = state.stages[roomNumber - 1]
        var target: DisplayInfo?
        if let displayNumber {
            let displays = liveOrderedDisplays
            guard displays.indices.contains(displayNumber - 1) else { return .failure("There is no display \(displayNumber). Run: tatami list displays") }
            target = displays[displayNumber - 1]
        }
        return .success(assignHome(target?.id, to: room.id))
    }

    /// Sets or clears where a Room lives, from the command or the Room settings sheet. Returns the message to show.
    @discardableResult func assignHome(_ displayID: String?, to roomID: UUID) -> String {
        guard let room = state.stages.first(where: { $0.id == roomID }) else { return "That Room no longer exists." }
        undoSnapshot = snapshot(name: "Before changing where a Room lives")
        state.setHome(displayID, for: roomID, displays: service.displays.map(\.id))
        persist()
        if managing {
            suppressFollowUntil = Date().addingTimeInterval(followSuppression)
            reportFailures(applyVisibility(), action: "update displays")
            applyLayouts()
            refocusIfParked()
        }
        publish()
        guard let displayID else { return "\(room.name) no longer lives on a display." }
        let name = service.displays.first { $0.id == displayID }?.name ?? "that display"
        return "\(room.name) now lives on \(name), and new windows of its apps open there as tabs. Each display shows its own Room now."
    }

    /// How new windows open in a Room (nil follows the default).
    func setRoomPlacement(_ placement: NewWindowPlacement?, for roomID: UUID) {
        state.setPlacement(placement, for: roomID)
        persist()
        publish()
    }

    /// Keeps every connected display on its home Room unless you switched it yourself. True when a display changed Room.
    @discardableResult func applyRoomHomes() -> Bool {
        let before = state.displayRooms
        state.applyHomes(connected: service.displays.map(\.id))
        guard state.displayRooms != before else { return false }
        persist()
        return true
    }

    /// Typing must never go to a parked window: when a display changes Room under the focused window, focus something visible.
    func refocusIfParked() {
        guard let id = service.focusedID(), let window = service.windows.first(where: { $0.id == id }), window.hidden != nil || !isShownOnItsDisplay(window) else { return }
        let display = displayKey(of: window)
        focusAfterSwitch(to: state.activeRoomID(on: display), on: display)
    }

    /// A window of a routed app that appears after management started is moved once to the display its Room lives on.
    /// Windows already open are left where they are, and so is a window you move afterwards. Apps without a routing rule,
    /// windows during a display change, and minimized or parked windows are never moved (the last two wait until they show).
    func sendNewWindowsHome() {
        let connected = service.displays.map(\.id)
        guard homesPrimed else {
            homeChecked = Set(service.windows.map(\.id))
            homesPrimed = true
            return
        }
        guard !service.displaysAreSettling else { return }
        for window in service.windows where !homeChecked.contains(window.id) {
            guard window.hidden == nil, !window.minimized, let current = service.display(for: window.frame) else { continue }  // try again later
            homeChecked.insert(window.id)
            guard !state.excludedBundleIDs.contains(window.bundleID),
                  state.destination(bundleID: window.bundleID, title: window.title) == window.stageID,
                  let homeKey = state.homeToMoveTo(room: window.stageID, currentDisplay: current.id, connected: connected),
                  let target = service.displays.first(where: { $0.id == homeKey }) else { continue }
            let frame = DisplayRemap.remap(window.frame, from: current.area, to: target.area)
            if service.place(window.id, at: frame) { _ = displayTracker.update(window: window.id, display: homeKey) }  // ours, not a drag
            else { notice = "\(window.appName) could not be moved to \(target.name)." }
        }
        let live = Set(service.windows.map(\.id))
        homeChecked = homeChecked.filter { live.contains($0) }
    }
}

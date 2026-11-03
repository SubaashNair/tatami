import AppKit
import TatamiCore

/// Per-display Rooms wiring (rules live in TatamiCore/RoomsPerDisplay.swift). With the setting off every call here
/// behaves exactly like the single active Room it replaced.
extension AppModel {
    /// Switches the Room on one display, or everywhere with the setting off (or when no display can be found).
    /// With per-display Rooms on and no display to act on, nothing changes: guessing could move every display.
    func setActiveRoom(_ id: UUID, on display: String?) {
        let shownOn = state.perDisplayRooms ? display : nil
        let old = state.activeRoomID(on: shownOn)
        if state.perDisplayRooms {
            guard let display else { return }
            state.switchRoom(id, on: display, displays: service.displays.map(\.id))
        } else {
            state.switchRoomEverywhere(id)
        }
        roomHistory.record(from: old, to: id, on: shownOn)
    }

    /// The previous-Room key: back to the Room this display showed before (the whole desk's, with per-display Rooms off).
    /// Pressing it again flips back.
    func goToPreviousRoom() {
        let display = state.perDisplayRooms ? targetDisplay()?.id : nil
        if state.perDisplayRooms && display == nil { return }
        let current = state.activeRoomID(on: display)
        guard let target = roomHistory.back(on: display, current: current, rooms: state.stages.map(\.id)) else {
            notice = state.perDisplayRooms ? "This display has no previous Room yet." : "There is no previous Room yet."
            return
        }
        switchStage(target, on: display)
    }

    /// The Room `offset` steps from the one showing on the display you are working on (the single active Room when off).
    func roomID(offset: Int) -> UUID { state.stageID(offset: offset, on: targetDisplay()?.id) }

    /// A window the user drags to another display joins the Room showing there, so it does not vanish on arrival.
    /// A display that was unplugged is not a drag: macOS moved those windows, and their Rooms stay as they were.
    func adoptRoomsOfMovedWindows() {
        displayTracker.keepOnly(Set(service.windows.map(\.id)))
        let connected = Set(service.displays.map(\.id))  // the live list: the published one lags a scan behind
        let settling = service.displaysAreSettling
        for index in service.windows.indices {
            let window = service.windows[index]
            guard window.hidden == nil, !window.minimized else { continue }
            let now = displayKey(of: window)
            guard let from = displayTracker.update(window: window.id, display: now) else { continue }
            // While macOS shuffles windows after a display change the move is recorded but is not the user dragging.
            guard state.perDisplayRooms, !settling, let now, connected.contains(from), !state.excludedBundleIDs.contains(window.bundleID) else { continue }
            let room = state.roomForWindowSent(to: now)
            if window.stageID != room { service.windows[index].stageID = room }
        }
    }

    /// The Preferences switch. Turning it on starts every display on the current Room; turning it off puts them all on the
    /// last switched Room. Windows are shown or hidden to match straight away.
    func setPerDisplayRooms(_ on: Bool) {
        guard on != state.perDisplayRooms else { return }
        state.setPerDisplayRooms(on)
        persist()
        if managing {
            suppressFollowUntil = Date().addingTimeInterval(followSuppression)
            reportFailures(applyVisibility(), action: "update displays")
            applyLayouts()
        }
        publish()
        notice = on ? "Each display can now show its own Room. Switch with \(state.shortcutPreset.stageModifiers)1–9 on the display you are working on."
                    : "Every display shows the same Room again."
    }
}

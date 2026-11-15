import AppKit
import TatamiCore

/// Send a Room to another display (AeroSpace's move-workspace-to-monitor). The two displays swap Rooms, so neither is left
/// without one: the Room on this display goes to the neighbour, its windows move with it, and the neighbour's Room comes here.
extension AppModel {
    func sendRoomToDisplay(offset: Int) {
        guard managing else { notice = "Start managing to send a Room to another display."; return }
        guard state.perDisplayRooms else {
            notice = "Turn on \"Each display shows its own Room\" (Preferences, Displays) to send a Room to another display."
            return
        }
        guard let source = targetDisplay(),
              let targetID = DisplayOrder.neighbour(of: source.id, offset: offset, in: service.displays.map { ($0.id, $0.fullFrame) }),
              let target = service.displays.first(where: { $0.id == targetID }) else { notice = "Only one display is connected."; return }
        let first = state.activeRoomID(on: source.id), second = state.activeRoomID(on: target.id)
        guard first != second else { notice = "\(target.name) already shows the same Room."; return }

        // The windows that follow their Room, found before anything changes (a parked one counts by where it will return to).
        // Always-visible apps stay where they are.
        let leaving = service.windows.filter { $0.stageID == first && displayKey(of: $0) == source.id && !state.excludedBundleIDs.contains($0.bundleID) }.map(\.id)
        let arriving = service.windows.filter { $0.stageID == second && displayKey(of: $0) == target.id && !state.excludedBundleIDs.contains($0.bundleID) }.map(\.id)

        guard state.swapRooms(between: source.id, and: target.id, displays: displayDescriptors()) != nil else { return }
        roomHistory.record(from: first, to: second, on: source.id)  // so the previous-Room key swaps them back
        roomHistory.record(from: second, to: first, on: target.id)
        suppressFollowUntil = Date().addingTimeInterval(followSuppression)

        // The Rooms' tab and pane layouts move with them.
        var carried: [(key: LayoutKey, layout: PaneLayout)] = []
        for (key, layout) in layouts {
            if key.stage == first && key.display == source.id { carried.append((LayoutKey(stage: first, display: target.id), layout)); layouts[key] = nil }
            else if key.stage == second && key.display == target.id { carried.append((LayoutKey(stage: second, display: source.id), layout)); layouts[key] = nil }
        }
        // A stale layout for a Room on the display it is arriving at would otherwise linger.
        layouts[LayoutKey(stage: first, display: target.id)] = nil
        layouts[LayoutKey(stage: second, display: source.id)] = nil
        for item in carried { layouts[item.key] = item.layout }

        var failures = 0
        func move(_ ids: [UUID], from: DisplayInfo, to: DisplayInfo) {
            for id in ids {
                guard let window = service.windows.first(where: { $0.id == id }) else { continue }
                let frame = DisplayRemap.remap(window.realFrame, from: from.area, to: to.area)
                if window.hidden != nil { service.setRealFrame(id, frame) }
                else if service.place(id, at: frame) { _ = displayTracker.update(window: id, display: to.id) }  // ours, not a drag
                else { failures += 1 }
                if let saved = freeformFrames[id] { freeformFrames[id] = DisplayRemap.remap(saved, from: from.area, to: to.area) }  // where it returns to on leaving Tiles
            }
        }
        move(leaving, from: source, to: target)
        move(arriving, from: target, to: source)

        persist()
        syncLayouts()  // drops any layout whose display is not in Tiles mode before layouts are applied
        reportFailures(failures + applyVisibility(), action: "send the Room")
        applyLayouts()
        refocusIfParked()
        publish()
        let names = state.stages.reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }
        notice = "\(names[first] ?? "The Room") is on \(target.name) now, and \(names[second] ?? "the other Room") on \(source.name). Send it back with the same key."
    }
}

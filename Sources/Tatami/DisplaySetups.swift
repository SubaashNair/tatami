import AppKit
import TatamiCore

/// Display setups wiring (rules live in TatamiCore/DisplaySetups.swift). The layout is saved per set of connected displays,
/// and put back by itself when the displays return to a setup Tatami knows, such as after waking from sleep.
extension AppModel {
    var displaySetupsURL: URL { directory.appendingPathComponent("setups.json") }
    private static let setupFlushInterval: TimeInterval = 10
    private static let setupMaxAge: TimeInterval = 120 * 86_400

    func loadDisplaySetups() {
        guard let data = try? Data(contentsOf: displaySetupsURL), var store = try? JSONDecoder().decode(DisplaySetupStore.self, from: data) else { return }
        store.prune(olderThan: Self.setupMaxAge, now: Date())
        displaySetups = store
    }

    /// Called with every checkpoint. Saves it for the current setup, but only while the desk is calm: while a display is
    /// missing, settling or about to be reconciled, macOS may have shuffled the windows. Unchanged layouts are not rewritten.
    func saveDisplaySetup(_ checkpoint: Checkpoint) {
        guard managing, !setupReconcilePending, !service.displaysAreSettling, displayPresence.pendingMissing.isEmpty else { return }
        let ids = service.displays.map(\.id)
        if let existing = displaySetups.setup(for: ids)?.checkpoint, existing.windows == checkpoint.windows, existing.activeStageID == checkpoint.activeStageID { return }
        guard displaySetups.save(checkpoint, displayKeys: ids, displayNames: orderedDisplays.map(\.name), at: Date()) else { return }
        if Date().timeIntervalSince(lastSetupFlush) >= Self.setupFlushInterval { flushDisplaySetups() }
    }

    /// Writes the remembered setups to disk (always, just before sleep and at quit), forgetting very old ones first.
    func flushDisplaySetups() {
        lastSetupFlush = Date()
        displaySetups.prune(olderThan: Self.setupMaxAge, now: Date())
        guard let data = try? JSONEncoder().encode(displaySetups) else { return }
        try? data.write(to: displaySetupsURL, options: .atomic)
    }

    /// After displays change or the Mac wakes: wait until everything has settled, then act on the setup now in front of us.
    func scheduleSetupReconcile(attempt: Int = 0) {
        setupReconcileWork?.cancel()
        setupReconcilePending = true
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.reconcileDisplaySetup(attempt: attempt) } }
        setupReconcileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 2 : 1), execute: work)
    }

    private func reconcileDisplaySetup(attempt: Int) {
        if service.displaysAreSettling || !displayPresence.pendingMissing.isEmpty {
            if attempt < 60 { scheduleSetupReconcile(attempt: attempt + 1) } else { setupReconcilePending = false }
            return
        }
        guard managing else {
            // Paused: nothing is restored, and nothing may be saved until it has been, or a shuffled layout would replace the good one.
            setupReconcileWhenManaging = true
            return
        }
        setupReconcilePending = false
        let ids = service.displays.map(\.id)
        let known = displaySetups.setup(for: ids)
        // A setup never seen before is only tracked, and "ask" keeps the old reconnect prompt.
        guard DisplaySetupRules.action(policy: state.displayChangePolicy, known: known != nil) == .restore, let known else { return }
        applyDisplaySetup(known)
    }

    /// Puts the windows back as saved for this setup: their tab and pane layouts and the position of the windows that are not
    /// in a layout. Rooms are left as they are now. Closed windows are skipped and new ones are left alone. Does nothing, and
    /// leaves your undo alone, when everything is already where it was saved. Has undo otherwise.
    func applyDisplaySetup(_ setup: DisplaySetup) {
        let connected = Set(service.displays.map(\.id))
        let checkpoint = setup.checkpoint
        let live = service.windows.map { LiveWindowKey(windowNumber: $0.windowNumber, pid: $0.pid, bundleID: $0.bundleID, title: $0.title) }
        // Inside one app run the window number is the identity: a new window that merely has the old one's title is not it.
        let matches = CheckpointWindow.match(saved: checkpoint.windows, live: live).filter { saved, index in
            let entry = checkpoint.windows[saved], window = service.windows[index]
            return entry.pid != window.pid || (entry.windowNumber != nil && entry.windowNumber == window.windowNumber)
        }
        var idMap: [UUID: UUID] = [:]
        for (saved, index) in matches { if let old = checkpoint.windows[saved].id { idMap[old] = service.windows[index].id } }

        // What would change: the layouts on connected displays, and the windows outside any layout that are not where they were.
        var candidate: [LayoutKey: PaneLayout] = [:]
        for entry in checkpoint.layouts ?? [] where connected.contains(entry.displayKey) && isTiled(stage: entry.stageID, display: entry.displayKey) {
            candidate[LayoutKey(stage: entry.stageID, display: entry.displayKey)] = entry.layout.remapped(idMap).pruned()
        }
        let current = layouts.filter { connected.contains($0.key.display) }
        let layoutsDiffer = candidate != current
        let tiledAfter = Set((layoutsDiffer ? candidate : current).values.flatMap(\.windows))
        var moves: [(id: UUID, frame: CGRect, display: String, hidden: Bool)] = []
        for (saved, index) in matches {
            let entry = checkpoint.windows[saved]
            let window = service.windows[index]
            guard !tiledAfter.contains(window.id), !window.minimized, let key = entry.displayKey,
                  let area = service.displays.first(where: { $0.id == key })?.area else { continue }
            let target = Geometry.visibleFrame(entry.frame.cgRect, in: area)  // never off screen, whatever changed on that display
            let now = window.realFrame
            guard abs(now.minX - target.minX) > 8 || abs(now.minY - target.minY) > 8 || abs(now.width - target.width) > 8 || abs(now.height - target.height) > 8 else { continue }
            moves.append((window.id, target, key, window.hidden != nil))
        }
        guard layoutsDiffer || !moves.isEmpty else { displaySetups.touch(setup.key, at: Date()); return }

        undoSnapshot = snapshot(name: "Before restoring \(setup.title)")
        suppressFollowUntil = Date().addingTimeInterval(followSuppression)
        if layoutsDiffer {
            for key in Array(layouts.keys) where connected.contains(key.display) { layouts[key] = nil }  // the saved ones replace them
            restoreLayouts((checkpoint.layouts ?? []).filter { connected.contains($0.displayKey) }, idMap: idMap)
        }
        var placed = 0
        for move in moves {
            if move.hidden { service.setRealFrame(move.id, move.frame); placed += 1 }
            else if service.place(move.id, at: move.frame) { placed += 1; _ = displayTracker.update(window: move.id, display: move.display) }  // ours, not a drag
        }
        for (id, entry) in displaced where connected.contains(entry.display) { displaced[id] = nil }
        for key in Array(detachedLayouts.keys) where connected.contains(key.display) { detachedLayouts[key] = nil }
        displaySetups.touch(setup.key, at: Date())
        windowsChanged()
        notice = "Restored your \(setup.title) layout (\(matches.count) window(s))."
    }
}

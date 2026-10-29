import AppKit
import TatamiCore

struct LayoutKey: Hashable {
    let stage: UUID
    let display: String
}

/// Tiles runtime (M3): per-Stage, per-display pane layouts applied to real windows.
extension AppModel {
    static let tabBarHeight: Double = 28
    private static let frameTolerance: CGFloat = 2
    private static let editRecheckDelay: TimeInterval = 0.15

    func isTiled(stage: UUID, display: String) -> Bool { state.tiledDisplays[stage.uuidString]?.contains(display) == true }

    func isFloating(_ window: LiveWindow) -> Bool {
        if let override = behaviorOverrides[window.id], override != .automatic { return override == .floating }
        return state.isFloating(bundleID: window.bundleID, title: window.title)
    }

    /// Windows a layout may hold: not excluded from staging, not floating, not minimized by the user.
    func isLayoutCandidate(_ window: LiveWindow) -> Bool {
        !state.excludedBundleIDs.contains(window.bundleID) && !isFloating(window) && !(window.minimized && window.hidden == nil)
    }

    /// Background tabs, and panes behind a zoomed pane, on the active Stage.
    func tabHiddenWindows() -> Set<UUID> {
        var hidden = Set<UUID>()
        for (key, layout) in layouts where key.stage == state.activeStageID {
            for pane in layout.root.panes {
                let paneShown = layout.zoomed == nil || layout.zoomed == pane.id
                for tab in pane.tabs where !paneShown || tab != pane.selected { hidden.insert(tab) }
            }
        }
        return hidden
    }

    func applyVisibility() -> Int { service.applyVisibility(state: state, extraHidden: tabHiddenWindows()) }

    func layoutKey(containing window: UUID) -> LayoutKey? { layouts.first { $0.value.pane(containing: window) != nil }?.key }

    /// The display a command should act on: the focused window's, else the one under the pointer.
    func targetDisplay() -> DisplayInfo? {
        if let id = service.focusedID(), let window = service.windows.first(where: { $0.id == id }), let display = service.display(for: window.realFrame) { return display }
        return displayUnderPointer() ?? service.displays.first
    }

    // MARK: mode switching (M3 decision 4)

    /// `chosen` is the display whose pane menu was used; shortcuts leave it nil and act on the focused display.
    func toggleWindowMode(on chosen: DisplayInfo? = nil) {
        guard managing else { notice = "Start managing to use Tiles."; return }
        guard let display = chosen ?? targetDisplay() else { return }
        let key = LayoutKey(stage: state.activeStageID, display: display.id)
        if isTiled(stage: key.stage, display: key.display) { leaveTiles(key, display: display) } else { enterTiles(key, display: display) }
    }

    private func enterTiles(_ key: LayoutKey, display: DisplayInfo) {
        let focused = service.focusedID()
        let members = service.windows
            .filter { $0.stageID == key.stage && $0.hidden == nil && isLayoutCandidate($0) && service.display(for: $0.frame)?.id == display.id }
            .sorted { a, _ in a.id == focused }
        for window in members { freeformFrames[window.id] = window.frame }
        layouts[key] = PaneLayout.balanced(windows: members.map(\.id), aspect: display.area.width / max(display.area.height, 1))
        state.tiledDisplays[key.stage.uuidString, default: []].append(key.display)
        persist()
        applyLayouts()
        notice = "Tiles is on for \(display.name). \(state.shortcutPreset == .classic ? "⌥B" : "⌃⌥B") switches back to Freeform."
    }

    private func leaveTiles(_ key: LayoutKey, display: DisplayInfo) {
        let members = layouts.removeValue(forKey: key)?.windows ?? []
        histories[key] = nil
        state.tiledDisplays[key.stage.uuidString]?.removeAll { $0 == key.display }
        if state.tiledDisplays[key.stage.uuidString]?.isEmpty == true { state.tiledDisplays[key.stage.uuidString] = nil }
        persist()
        reportFailures(applyVisibility(), action: "show background tabs")
        // Back to where each window was before Tiles; windows that joined later stay where they are.
        for id in members { if let frame = freeformFrames.removeValue(forKey: id) { service.move(id, to: frame) } }
        onLayoutsApplied?()
        publish()
        notice = "Freeform is back on \(display.name)."
    }

    // MARK: keeping layouts in step with windows

    /// Drops windows that closed, left the Stage, or started floating; places new ones (M3 decision 9).
    @discardableResult func syncLayouts() -> Bool {
        let byID = Dictionary(uniqueKeysWithValues: service.windows.map { ($0.id, $0) })
        var changed = false
        for key in Array(layouts.keys) {
            guard state.stages.contains(where: { $0.id == key.stage }), isTiled(stage: key.stage, display: key.display) else {
                layouts[key] = nil; changed = true; continue
            }
            var layout = layouts[key]!
            for id in layout.windows {
                guard let window = byID[id], window.stageID == key.stage, isLayoutCandidate(window) else {
                    layout.remove(id, keepEmptyPanes: state.keepEmptyPanes); changed = true; continue
                }
            }
            layouts[key] = layout
        }
        let placed = Set(layouts.values.flatMap(\.windows))
        for window in service.windows where !placed.contains(window.id) && window.hidden == nil && isLayoutCandidate(window) {
            guard let display = service.display(for: window.frame), isTiled(stage: window.stageID, display: display.id) else { continue }
            let key = LayoutKey(stage: window.stageID, display: display.id)
            var layout = layouts[key] ?? PaneLayout(root: .pane(Pane()))
            layout.place(window.id, policy: state.newWindowPlacement, in: display.area)
            layouts[key] = layout
            changed = true
        }
        return changed
    }

    /// Edits are judged only after the mouse is released, so Tatami never fights a drag in progress
    /// or an app that clamps its own size (M3 decision 14).
    func checkLayoutEdits() -> Bool {
        if NSEvent.pressedMouseButtons != 0 {
            userEditingLayout = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.editRecheckDelay) { [weak self] in
                MainActor.assumeIsolated { if self?.checkLayoutEdits() == true { self?.applyLayouts() } }
            }
            return false
        }
        guard userEditingLayout else { return false }
        userEditingLayout = false
        var changed = false
        for (key, layout) in layouts where key.stage == state.activeStageID {
            guard let display = service.displays.first(where: { $0.id == key.display }) else { continue }
            var edited = layout
            for pane in layout.root.panes {
                guard let id = pane.selected, let expected = expectedFrames[id],
                      let window = service.windows.first(where: { $0.id == id }), window.hidden == nil else { continue }
                let actual = window.frame
                let resized = abs(actual.width - expected.width) > 3 || abs(actual.height - expected.height) > 3
                let moved = abs(actual.minX - expected.minX) > 3 || abs(actual.minY - expected.minY) > 3
                if resized && !minSizeWindows.contains(id) {
                    edited.applyEdgeDrag(pane: pane.id, expected: expected, actual: actual, in: display.area, gap: state.gap, tabBar: Self.tabBarHeight)
                }
                if resized || moved { changed = true }  // a plain move snaps back; M4 adds drop targets
            }
            if edited != layout { recordHistory(key); layouts[key] = edited }
        }
        return changed
    }

    // MARK: applying layouts

    /// Places every pane's selected window and parks the rest. Hidden tabs are pointed at their pane first,
    /// so un-parking one later lands it in place.
    func applyLayouts() {
        guard managing else { onLayoutsApplied?(); return }
        var targets: [UUID: CGRect] = [:]
        for (key, layout) in layouts where key.stage == state.activeStageID {
            guard let display = service.displays.first(where: { $0.id == key.display }) else { continue }
            let frames = layout.frames(in: display.area, gap: state.gap, tabBar: Self.tabBarHeight)
            for pane in layout.root.panes {
                guard let frame = frames[pane.id]?.window else { continue }
                for tab in pane.tabs { targets[tab] = frame }
            }
        }
        let hidden = tabHiddenWindows()
        for (id, frame) in targets where hidden.contains(id) { service.setRealFrame(id, frame) }
        var failures = applyVisibility()
        for (id, frame) in targets where !hidden.contains(id) {
            guard let window = service.windows.first(where: { $0.id == id }), window.hidden == nil else { continue }
            expectedFrames[id] = frame
            if !Self.close(window.frame, frame) && !service.move(id, to: frame) { failures += 1 }
            // Apps with a minimum size stay at it, anchored top-left, with a warning on the tab (M3 decision 7).
            if let actual = service.windows.first(where: { $0.id == id })?.frame,
               actual.width > frame.width + Self.frameTolerance || actual.height > frame.height + Self.frameTolerance {
                minSizeWindows.insert(id)
            } else { minSizeWindows.remove(id) }
        }
        reportFailures(failures, action: "arrange Tiles")
        raiseFloats(activate: false)
        onLayoutsApplied?()
        publish()
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= frameTolerance && abs(a.minY - b.minY) <= frameTolerance
            && abs(a.width - b.width) <= frameTolerance && abs(a.height - b.height) <= frameTolerance
    }

    /// Floating windows on Tiles displays come back above the tiles (M3 decision 15).
    /// Raising alone keeps focus where it is; the Raise Floats shortcut also activates their apps.
    func raiseFloats(activate: Bool) {
        let floats = service.windows.filter { window in
            window.stageID == state.activeStageID && window.hidden == nil && isFloating(window) &&
                service.display(for: window.frame).map { isTiled(stage: state.activeStageID, display: $0.id) } == true
        }
        guard !floats.isEmpty else { return }
        service.raise(floats.map(\.id))
        guard activate else { return }
        let previous = service.focusedID()
        for pid in Set(floats.map(\.pid)) { NSRunningApplication(processIdentifier: pid)?.activate() }
        if let previous { service.focus(previous) }
    }

    func recordHistory(_ key: LayoutKey) {
        guard let layout = layouts[key] else { return }
        histories[key, default: LayoutHistory()].record(layout)
    }

    /// Mutates the focused display's layout on the active Stage with undo, then applies it.
    func mutateLayout(_ change: (inout PaneLayout, DisplayInfo) -> Void) {
        guard managing, let display = targetDisplay() else { return }
        let key = LayoutKey(stage: state.activeStageID, display: display.id)
        guard layouts[key] != nil else { notice = "\(display.name) is in Freeform. \(state.shortcutPreset == .classic ? "⌥B" : "⌃⌥B") turns on Tiles."; return }
        mutate(key, followFocus: true, change)
    }

    /// Mutates one layout with undo, applies it, and focuses its focused pane.
    func mutate(_ key: LayoutKey, followFocus: Bool = false, _ change: (inout PaneLayout, DisplayInfo) -> Void) {
        guard managing, var layout = layouts[key], let display = service.displays.first(where: { $0.id == key.display }) else { return }
        if followFocus, let id = service.focusedID(), layout.pane(containing: id) != nil { layout.select(id) }
        let before = layout
        change(&layout, display)
        guard layout != before else { return }
        histories[key, default: LayoutHistory()].record(before)
        layouts[key] = layout
        applyLayouts()
        if let selected = layout.root.pane(layout.focused)?.selected { service.focus(selected) }
    }

    func undoLayout() {
        guard let display = targetDisplay() else { return }
        undoLayout(key: LayoutKey(stage: state.activeStageID, display: display.id))
    }

    /// Undo for one display's layout, as chosen from that display's pane menu.
    func undoLayout(key: LayoutKey) {
        guard let previous = histories[key]?.undo() else { notice = "Nothing to undo in this layout."; return }
        layouts[key] = previous
        // A window lives in one layout. If the snapshot holds one that has since moved to another display, the restored layout wins.
        for other in Array(layouts.keys) where other != key {
            for id in previous.windows { layouts[other]?.remove(id, keepEmptyPanes: state.keepEmptyPanes) }
        }
        syncLayouts()  // windows may have closed since that step
        applyLayouts()
    }

    /// Cmd+Tab or a click reached a window in a layout: select its tab (showing it if it was in the background).
    func noteLayoutFocus(_ id: UUID) -> Bool {
        guard let key = layoutKey(containing: id), key.stage == state.activeStageID, var layout = layouts[key] else { return false }
        let wasHidden = tabHiddenWindows().contains(id)
        layout.select(id)
        if wasHidden, layout.zoomed != nil, layout.zoomed != layout.pane(containing: id)?.id { layout.zoomed = nil }
        layouts[key] = layout
        if wasHidden { applyLayouts(); service.focus(id) }
        return true
    }

    // MARK: keyboard navigation (TIL-06): panes of every Tiles display on the active Stage

    private func allPanes() -> [(key: LayoutKey, pane: UUID, frame: CGRect)] {
        layouts.filter { $0.key.stage == state.activeStageID }.flatMap { key, layout -> [(key: LayoutKey, pane: UUID, frame: CGRect)] in
            guard let display = service.displays.first(where: { $0.id == key.display }) else { return [] }
            return layout.frames(in: display.area, gap: state.gap, tabBar: Self.tabBarHeight).map { (key, $0.key, $0.value.pane) }
        }
    }

    /// The pane holding the focused window, or the focused pane of the target display's layout.
    private func currentPane() -> (key: LayoutKey, pane: UUID, window: UUID?)? {
        if let id = service.focusedID(), let key = layoutKey(containing: id), key.stage == state.activeStageID, let pane = layouts[key]?.pane(containing: id) {
            return (key, pane.id, id)
        }
        guard let display = targetDisplay() else { return nil }
        let key = LayoutKey(stage: state.activeStageID, display: display.id)
        guard let layout = layouts[key] else { return nil }
        return (key, layout.focused, layout.root.pane(layout.focused)?.selected)
    }

    /// False when no pane lies that way, so the caller can fall back to windows by position.
    @discardableResult func focusPane(_ direction: Direction) -> Bool {
        guard let current = currentPane() else { return false }
        let panes = allPanes()
        guard let from = panes.first(where: { $0.pane == current.pane })?.frame,
              let target = PaneLayout.neighbour(of: from, toward: direction, among: panes.filter { $0.pane != current.pane }.map { ($0.pane, $0.frame) }),
              let key = panes.first(where: { $0.pane == target })?.key else { return false }
        layouts[key]?.focused = target
        if let window = layouts[key]?.root.pane(target)?.selected { service.focus(window) }
        onLayoutsApplied?()
        return true
    }

    /// Moves the focused window to the neighbouring pane, across displays too; it keeps focus.
    @discardableResult func moveToPane(_ direction: Direction) -> Bool {
        guard let current = currentPane(), let window = current.window else { return false }
        let panes = allPanes()
        guard let from = panes.first(where: { $0.pane == current.pane })?.frame,
              let target = PaneLayout.neighbour(of: from, toward: direction, among: panes.filter { $0.pane != current.pane }.map { ($0.pane, $0.frame) }),
              let targetKey = panes.first(where: { $0.pane == target })?.key else { return false }
        if targetKey == current.key {
            mutate(current.key) { layout, _ in layout.move(window, to: target, keepEmptyPanes: state.keepEmptyPanes) }
        } else {
            recordHistory(current.key); recordHistory(targetKey)
            layouts[current.key]?.remove(window, keepEmptyPanes: state.keepEmptyPanes)
            layouts[targetKey]?.add(window, to: target)
            freeformFrames[window] = nil  // it joined this layout later, so leaving Tiles leaves it where it is
            applyLayouts()
        }
        service.focus(window)
        return true
    }

    /// M3 decision 13: in Tiles, arrow snaps move a managed window to the neighbouring pane; other snaps do nothing.
    func snapInLayout(_ zone: SnapZone) -> Bool {
        guard let id = service.focusedID(), let key = layoutKey(containing: id), key.stage == state.activeStageID else { return false }
        let directions: [SnapZone: Direction] = [.left: .left, .right: .right, .top: .up, .bottom: .down]
        if let direction = directions[zone] { moveToPane(direction) }
        return true
    }

    // MARK: tab bar actions

    func selectTab(_ id: UUID) {
        guard let key = layoutKey(containing: id) else { return }
        mutate(key) { layout, _ in layout.select(id) }
        service.focus(id)
    }

    func closeTabs(_ ids: [UUID]) { ids.forEach(service.close) }

    func closeOtherTabs(_ id: UUID) {
        guard let pane = layoutKey(containing: id).flatMap({ layouts[$0]?.pane(containing: id) }) else { return }
        closeTabs(pane.tabs.filter { $0 != id })
    }

    func closeTabsToRight(_ id: UUID) {
        guard let pane = layoutKey(containing: id).flatMap({ layouts[$0]?.pane(containing: id) }), let index = pane.tabs.firstIndex(of: id) else { return }
        closeTabs(Array(pane.tabs.dropFirst(index + 1)))
    }

    /// Keep Floating / Manage in Layout (M3 decision 8), optionally saved as a rule for the app.
    func setBehavior(_ id: UUID, _ behavior: WindowBehavior, saveRule: Bool) {
        guard let window = service.windows.first(where: { $0.id == id }) else { return }
        behaviorOverrides[id] = behavior
        if saveRule {
            state.behaviorRules.removeAll { $0.bundleID == window.bundleID && $0.titleContains.isEmpty }
            state.behaviorRules.insert(WindowBehaviorRule(bundleID: window.bundleID, behavior: behavior), at: 0)
            persist()
        }
        syncLayouts(); applyLayouts()
        if behavior == .floating, let area = service.display(for: window.frame)?.area {
            service.move(id, to: Geometry.visibleFrame(CGRect(x: area.midX - window.frame.width / 4, y: area.midY - window.frame.height / 4,
                                                               width: window.frame.width / 2, height: window.frame.height / 2), in: area))
        }
        notice = behavior == .floating ? "\(window.appName) window floats\(saveRule ? "; new \(window.appName) windows will too" : "")." : "\(window.appName) window is managed in the layout."
    }

    func splitTab(_ id: UUID, axis: Axis) {
        guard let key = layoutKey(containing: id) else { return }
        mutate(key) { layout, _ in if let pane = layout.pane(containing: id), pane.tabs.count > 1 { layout.split(pane.id, axis: axis, moving: id) } }
    }

    func paneAction(_ key: LayoutKey, _ change: @escaping (inout PaneLayout, DisplayInfo) -> Void) { mutate(key, change) }

    // MARK: persistence (M3 decision 11)

    func savedLayouts() -> [SavedLayout] {
        layouts.map { SavedLayout(stageID: $0.key.stage, displayKey: $0.key.display, layout: $0.value) }
    }

    func restoreLayouts(_ saved: [SavedLayout], idMap: [UUID: UUID]) {
        for entry in saved where isTiled(stage: entry.stageID, display: entry.displayKey) {
            layouts[LayoutKey(stage: entry.stageID, display: entry.displayKey)] = entry.layout.remapped(idMap).pruned()
        }
    }
}

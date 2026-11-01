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

    func isTiled(stage: UUID, display: String) -> Bool { state.isTiled(stage: stage, display: display) }

    /// Turns "tile new windows automatically" on or off. Turning it off sends every display that was only tiled
    /// by default back to Freeform, with its windows where they were; displays tiled by key stay tiled.
    func setTilesByDefault(_ on: Bool) {
        guard on != state.tilesByDefault else { return }
        let tiledNow = layouts.keys.filter { isTiled(stage: $0.stage, display: $0.display) }
        state.tilesByDefault = on
        for key in tiledNow where !isTiled(stage: key.stage, display: key.display) {
            if let display = service.displays.first(where: { $0.id == key.display }) { leaveTiles(key, display: display) }
        }
        persist()
        if managing { syncLayouts(); applyLayouts() } else { publish() }
        notice = on ? "New windows now tile automatically." : "Windows stay where you put them. Tiles is still available per display."
    }

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
        for (key, layout) in layouts where state.isActiveRoom(key.stage, on: key.display) {
            for pane in layout.root.panes {
                let paneShown = layout.zoomed == nil || layout.zoomed == pane.id
                for tab in pane.tabs where !paneShown || tab != pane.selected { hidden.insert(tab) }
            }
        }
        return hidden
    }

    /// The display a window sits on, by its real frame (a parked window keeps the frame it will return to).
    func displayKey(of window: LiveWindow) -> String? { service.display(for: window.realFrame)?.id }

    /// Whether a window's Room is the one showing on the display it sits on. With per-display Rooms off this is the old
    /// single active Room check.
    func isShownOnItsDisplay(_ window: LiveWindow) -> Bool { state.isVisible(room: window.stageID, bundleID: window.bundleID, on: displayKey(of: window)) }

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
        let key = LayoutKey(stage: state.activeRoomID(on: display.id), display: display.id)
        if isTiled(stage: key.stage, display: key.display) { leaveTiles(key, display: display) } else { enterTiles(key, display: display) }
    }

    private func enterTiles(_ key: LayoutKey, display: DisplayInfo) {
        let focused = service.focusedID()
        let members = service.windows
            .filter { $0.stageID == key.stage && $0.hidden == nil && isLayoutCandidate($0) && service.display(for: $0.frame)?.id == display.id }
            .sorted { a, _ in a.id == focused }
        for window in members { freeformFrames[window.id] = window.frame }
        layouts[key] = PaneLayout.balanced(windows: members.map(\.id), aspect: display.area.width / max(display.area.height, 1))
        state.setTiled(true, stage: key.stage, display: key.display)
        persist()
        applyLayouts()
        notice = "Tiles is on for \(display.name). \(state.shortcutPreset == .classic ? "⌥B" : "⌃⌥B") switches back to Freeform."
    }

    private func leaveTiles(_ key: LayoutKey, display: DisplayInfo) {
        let members = layouts.removeValue(forKey: key)?.windows ?? []
        histories[key] = nil
        state.setTiled(false, stage: key.stage, display: key.display)
        persist()
        reportFailures(applyVisibility(), action: "show background tabs")
        // Back to where each window was before Tiles; windows that joined later stay where they are.
        // place() so a window parked on an inactive Stage gets its return frame recorded instead of jumping on screen.
        for id in members { if let frame = freeformFrames.removeValue(forKey: id) { service.place(id, at: frame) } }
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
            // Remember where it was, so switching the display to Freeform puts it back (as when Tiles is entered by key).
            freeformFrames[window.id] = window.frame  // always current: it is joining a layout now, so any old entry is stale
            layout.place(window.id, policy: state.placement(forRoom: window.stageID), in: display.area)
            layouts[key] = layout
            changed = true
        }
        freeformFrames = freeformFrames.filter { byID[$0.key] != nil }  // closed windows leave no entry behind
        behaviorOverrides = behaviorOverrides.filter { byID[$0.key] != nil }
        minSizeWindows = minSizeWindows.filter { byID[$0] != nil }
        knownMinSizes = knownMinSizes.filter { byID[$0.key] != nil }
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
        for (key, layout) in layouts where state.isActiveRoom(key.stage, on: key.display) {
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
        for (key, layout) in layouts where state.isActiveRoom(key.stage, on: key.display) {
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
        var oversized: [UUID: CGSize] = [:]
        for (id, frame) in targets where !hidden.contains(id) {
            guard let window = service.windows.first(where: { $0.id == id }), window.hidden == nil else { continue }
            expectedFrames[id] = frame
            if !Self.close(window.frame, frame) && !service.move(id, to: frame) { failures += 1 }
            // Apps with a minimum size stay at it, anchored top-left, with a warning on the tab (M3 decision 7).
            if let actual = service.windows.first(where: { $0.id == id })?.frame,
               actual.width > frame.width + Self.frameTolerance || actual.height > frame.height + Self.frameTolerance {
                minSizeWindows.insert(id)
                oversized[id] = actual.size
            } else { minSizeWindows.remove(id) }
        }
        reportFailures(failures, action: "arrange Tiles")
        if !oversized.isEmpty, !fittingOversized { scheduleOversizedCheck() }
        raiseFloats(activate: false)
        onLayoutsApplied?()
        publish()
    }

    private static let oversizedDelay: TimeInterval = 0.4
    /// Overflowing by less than this is left alone (a tab bar and gap off by a few points): not worth floating a window for.
    private static let overflowLeeway: CGFloat = 24

    /// A window can report its old size for a moment after being resized, so nothing is decided on the first look:
    /// the check runs shortly after, on fresh sizes, and waits out any mouse drag.
    private func scheduleOversizedCheck() {
        guard !oversizedCheckPending else { return }
        oversizedCheckPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.oversizedDelay) { [weak self] in
            MainActor.assumeIsolated { self?.checkOversized() }
        }
    }

    private func checkOversized() {
        oversizedCheckPending = false
        guard managing else { return }
        if NSEvent.pressedMouseButtons != 0 { scheduleOversizedCheck(); return }  // never fight the user's own resizing
        var oversized: [UUID: CGSize] = [:]
        for id in minSizeWindows {
            guard let expected = expectedFrames[id], let live = service.liveFrame(id) else { continue }
            if live.width > expected.width + Self.frameTolerance || live.height > expected.height + Self.frameTolerance { oversized[id] = live.size }
        }
        if !oversized.isEmpty { _ = makeRoom(for: oversized) }
    }

    /// Windows that cannot shrink to their pane (Photo Booth, apps with a minimum size) would spill over the neighbouring pane.
    /// Grow their pane first; if no room can be made, float them. Runs once per layout pass, so it cannot loop.
    /// Returns true when it changed something and re-applied the layouts.
    private func makeRoom(for oversized: [UUID: CGSize]) -> Bool {
        fittingOversized = true
        defer { fittingOversized = false }
        for (id, size) in oversized { knownMinSizes[id] = size }
        var changed = false
        var floated: [(window: LiveWindow, size: CGSize)] = []
        // Biggest demand first, so the order does not depend on dictionary order.
        for (id, size) in oversized.sorted(by: { $0.value.width + $0.value.height > $1.value.width + $1.value.height }) {
            guard let key = layoutKey(containing: id), state.isActiveRoom(key.stage, on: key.display), var layout = layouts[key],
                  let pane = layout.pane(containing: id), let display = service.displays.first(where: { $0.id == key.display }) else { continue }
            let minimums = Dictionary(uniqueKeysWithValues: layout.root.panes.compactMap { other -> (UUID, CGSize)? in
                guard other.id != pane.id, let selected = other.selected, let known = knownMinSizes[selected] else { return nil }
                return (other.id, known)
            })
            let before = layout
            if layout.fit(pane.id, toWindowSize: size, in: display.area, gap: state.gap, tabBar: Self.tabBarHeight, keeping: minimums) {
                if layout != before { recordHistory(key); layouts[key] = layout; changed = true }
            } else if let window = service.windows.first(where: { $0.id == id }) {
                if let expected = expectedFrames[id], size.width <= expected.width + Self.overflowLeeway, size.height <= expected.height + Self.overflowLeeway { continue }
                behaviorOverrides[id] = .floating
                floated.append((window, size))
                changed = true
            }
        }
        guard changed else { return false }
        syncLayouts()
        applyLayouts()
        // Keep the window at its own size: the app would refuse half of it anyway.
        for (index, entry) in floated.enumerated() { centreAsFloat(entry.window, cascade: index, size: entry.size) }
        if let first = floated.first {
            notice = "\(first.window.appName) cannot shrink to a pane, so it floats. \(state.shortcutPreset == .classic ? "⌘⌥T" : "⌃⌥⌘T") tiles it again."
        }
        publish()
        onLayoutsApplied?()
        return true
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= frameTolerance && abs(a.minY - b.minY) <= frameTolerance
            && abs(a.width - b.width) <= frameTolerance && abs(a.height - b.height) <= frameTolerance
    }

    /// Floating windows on Tiles displays come back above the tiles (M3 decision 15).
    /// Raising alone keeps focus where it is; the Raise Floats shortcut also activates their apps.
    func raiseFloats(activate: Bool) {
        let floats = service.windows.filter { window in
            window.hidden == nil && isFloating(window) &&
                service.display(for: window.frame).map { state.isActiveRoom(window.stageID, on: $0.id) && isTiled(stage: window.stageID, display: $0.id) } == true
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
        let key = LayoutKey(stage: state.activeRoomID(on: display.id), display: display.id)
        guard isTiled(stage: key.stage, display: key.display) else { notice = "\(display.name) is in Freeform. \(state.shortcutPreset == .classic ? "⌥B" : "⌃⌥B") turns on Tiles."; return }
        if layouts[key] == nil { layouts[key] = PaneLayout(root: .pane(Pane())) }  // a tiled display with no windows yet
        mutate(key, followFocus: true, change)
        // A command that changed nothing must not leave an empty layout, and so an empty tab bar, on a display with no windows.
        if let layout = layouts[key], layout.windows.isEmpty, layout.root.panes.count == 1 { layouts[key] = nil }
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
        undoLayout(key: LayoutKey(stage: state.activeRoomID(on: display.id), display: display.id))
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
        guard let key = layoutKey(containing: id), state.isActiveRoom(key.stage, on: key.display), var layout = layouts[key] else { return false }
        let wasHidden = tabHiddenWindows().contains(id)
        layout.select(id)
        if wasHidden, layout.zoomed != nil, layout.zoomed != layout.pane(containing: id)?.id { layout.zoomed = nil }
        layouts[key] = layout
        if wasHidden { applyLayouts(); service.focus(id) }
        return true
    }

    // MARK: keyboard navigation (TIL-06): panes of every Tiles display on the active Stage

    private func allPanes() -> [(key: LayoutKey, pane: UUID, frame: CGRect)] {
        layouts.filter { state.isActiveRoom($0.key.stage, on: $0.key.display) }.flatMap { key, layout -> [(key: LayoutKey, pane: UUID, frame: CGRect)] in
            guard let display = service.displays.first(where: { $0.id == key.display }) else { return [] }
            return layout.frames(in: display.area, gap: state.gap, tabBar: Self.tabBarHeight).map { (key, $0.key, $0.value.pane) }
        }
    }

    /// The pane holding the focused window, or the focused pane of the target display's layout.
    private func currentPane() -> (key: LayoutKey, pane: UUID, window: UUID?)? {
        if let id = service.focusedID(), let key = layoutKey(containing: id), state.isActiveRoom(key.stage, on: key.display), let pane = layouts[key]?.pane(containing: id) {
            return (key, pane.id, id)
        }
        guard let display = targetDisplay() else { return nil }
        let key = LayoutKey(stage: state.activeRoomID(on: display.id), display: display.id)
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
        moveWindow(window, from: current.key, to: target, in: targetKey)
        return true
    }

    /// Moves a window into another pane, on this display or another one; it keeps focus.
    private func moveWindow(_ window: UUID, from sourceKey: LayoutKey, to target: UUID, in targetKey: LayoutKey) {
        if targetKey == sourceKey {
            mutate(sourceKey) { layout, _ in layout.move(window, to: target, keepEmptyPanes: state.keepEmptyPanes) }
        } else {
            recordHistory(sourceKey); recordHistory(targetKey)
            layouts[sourceKey]?.remove(window, keepEmptyPanes: state.keepEmptyPanes)
            layouts[targetKey]?.add(window, to: target)
            freeformFrames[window] = nil  // it joined this layout later, so leaving Tiles leaves it where it is
            applyLayouts()
        }
        service.focus(window)
    }

    // MARK: panes by number

    /// Panes of the active Stage in reading order across every tiled display, ignoring any zoom, so numbers stay put.
    private func numberedPanes() -> [(key: LayoutKey, pane: UUID)] {
        let panes = layouts.filter { state.isActiveRoom($0.key.stage, on: $0.key.display) }.flatMap { key, layout -> [(key: LayoutKey, pane: UUID, frame: CGRect)] in
            guard let display = service.displays.first(where: { $0.id == key.display }) else { return [] }
            return layout.paneRects(in: display.area).map { (key: key, pane: $0.key, frame: $0.value) }
        }
        let order = WindowFocus.readingOrder(panes.map { (id: $0.pane, frame: $0.frame) }, displays: service.displays.map(\.fullFrame))
        return order.compactMap { id in panes.first { $0.pane == id }.map { (key: $0.key, pane: id) } }
    }

    /// 1, 2, 3… for the tab-bar badge and the number keys; nil for a pane that is not on the active Stage.
    func paneNumber(_ pane: UUID) -> Int? { numberedPanes().firstIndex { $0.pane == pane }.map { $0 + 1 } }

    func focusPane(number: Int) {
        let panes = numberedPanes()
        guard panes.indices.contains(number - 1) else { notice = "There is no pane \(number)."; return }
        let target = panes[number - 1]
        // A zoomed layout hides every other pane, so going to one means leaving the zoom.
        if let zoomed = layouts[target.key]?.zoomed, zoomed != target.pane { layouts[target.key]?.zoomed = nil; applyLayouts() }
        layouts[target.key]?.focused = target.pane
        if let window = layouts[target.key]?.root.pane(target.pane)?.selected { service.focus(window) } else { notice = "Pane \(number) is empty." }
        onLayoutsApplied?()
    }

    func moveToPane(number: Int) {
        let panes = numberedPanes()
        guard panes.indices.contains(number - 1) else { notice = "There is no pane \(number)."; return }
        // currentPane() falls back to a display's focused pane when the focused window is not tiled (floating, excluded,
        // freeform); moving that pane's window instead would surprise, so require a focused tiled window.
        if let focused = service.focusedID(), layoutKey(containing: focused) == nil { notice = "Focus a tiled window first."; return }
        guard let current = currentPane(), let window = current.window else { notice = "Focus a tiled window first."; return }
        let target = panes[number - 1]
        guard target.pane != current.pane else { return }
        if let zoomed = layouts[target.key]?.zoomed, zoomed != target.pane { layouts[target.key]?.zoomed = nil }  // the arriving tab must show
        moveWindow(window, from: current.key, to: target.pane, in: target.key)
    }

    /// Turns the focused pane's split the other way: side by side becomes stacked and back.
    func rotateSplit() { mutateLayout { layout, _ in layout.rotateSplit(of: layout.focused) } }

    /// M3 decision 13: in Tiles, arrow snaps move a managed window to the neighbouring pane; other snaps do nothing.
    func snapInLayout(_ zone: SnapZone) -> Bool {
        guard let id = service.focusedID(), let key = layoutKey(containing: id), state.isActiveRoom(key.stage, on: key.display) else { return false }
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
        if behavior == .floating { centreAsFloat(window) }
        notice = behavior == .floating ? "\(window.appName) window floats\(saveRule ? "; new \(window.appName) windows will too" : "")." : "\(window.appName) window is managed in the layout."
    }

    /// A window leaving the tiles lands in the middle of its display at half its tiled size, so it is easy to see.
    /// `cascade` steps several windows apart so they do not sit exactly on top of each other.
    /// `size` keeps a window at a size it cannot go below; without it the window is halved.
    private func centreAsFloat(_ window: LiveWindow, cascade: Int = 0, size: CGSize? = nil) {
        guard let area = service.display(for: window.frame)?.area else { return }
        let step = CGFloat(cascade) * 28
        let target = size ?? CGSize(width: window.frame.width / 2, height: window.frame.height / 2)
        let width = min(target.width, area.width), height = min(target.height, area.height)
        service.move(window.id, to: Geometry.visibleFrame(CGRect(x: area.midX - width / 2 + step, y: area.midY - height / 2 + step, width: width, height: height), in: area))
    }

    /// Float and tile only mean something for a window on a tiled display while Tatami is managing; elsewhere the keys
    /// would just shrink a window that never was in the tiles.
    private func focusedTileableWindow() -> LiveWindow? {
        guard let id = service.focusedID(), let window = service.windows.first(where: { $0.id == id }) else { notice = "Focus a window first."; return nil }
        guard managing, !state.excludedBundleIDs.contains(window.bundleID), !window.minimized,
              service.display(for: window.frame).map({ isTiled(stage: window.stageID, display: $0.id) }) == true else {
            notice = "Float and tile apply to windows on a tiled display while Tatami is managing."
            return nil
        }
        return window
    }

    /// One key: float the focused window if it is tiled, tile it if it floats.
    func toggleFloating() {
        guard let window = focusedTileableWindow() else { return }
        setBehavior(window.id, isFloating(window) ? .managed : .floating, saveRule: false)
    }

    /// The same for every window of the focused window's app, saved as a rule. A second press undoes it.
    func toggleFloatingForApp() {
        guard let window = focusedTileableWindow() else { return }
        let siblings = service.windows.filter { $0.bundleID == window.bundleID && $0.hidden == nil && !$0.minimized }
        let wasFloating = Set(siblings.filter(isFloating).map(\.id))
        let floats = state.toggleAppBehavior(bundleID: window.bundleID)
        for other in service.windows where other.bundleID == window.bundleID { behaviorOverrides[other.id] = nil }  // the rule decides now
        persist()
        syncLayouts(); applyLayouts()
        // Only windows that really went from tiled to floating are moved, each a little apart from the last.
        let moved = siblings.filter { !wasFloating.contains($0.id) && isFloating($0) }
        for (index, sibling) in moved.enumerated() { centreAsFloat(sibling, cascade: index) }
        notice = floats ? "\(window.appName) windows float." : "\(window.appName) windows tile."
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

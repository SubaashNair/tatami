import AppKit
import TatamiCore

/// Sending a window to another display, from the tab and pane menus or a shortcut.
extension AppModel {
    /// Displays in arrangement order (left to right, then top to bottom), as the menus list them.
    var orderedDisplays: [DisplayInfo] {
        DisplayOrder.ordered(displays.map { ($0.id, $0.fullFrame) }).compactMap { id in displays.first { $0.id == id } }
    }

    /// Moves the focused window to the next or previous display.
    func sendFocusedWindowToDisplay(offset: Int) {
        guard let id = service.focusedID(), let window = service.windows.first(where: { $0.id == id }),
              let current = service.display(for: window.frame) else { notice = "Focus a window first."; return }
        guard let targetID = DisplayOrder.neighbour(of: current.id, offset: offset, in: service.displays.map { ($0.id, $0.fullFrame) }),
              let target = service.displays.first(where: { $0.id == targetID }) else { notice = "Only one display is connected."; return }
        sendWindow(id, to: target)
    }

    /// A tiled display takes the window as a tab in its focused pane; a freeform display gets it at the same
    /// relative position and size. Background tabs work too. A window on another Stage that is in no layout is left alone.
    /// Layout undo does not reverse a send (it spans two layouts): send the window back instead.
    func sendWindow(_ id: UUID, to target: DisplayInfo) {
        guard let window = service.windows.first(where: { $0.id == id }) else { return }
        let sourceKey = layoutKey(containing: id)
        guard window.hidden == nil || sourceKey != nil else { notice = "\(window.appName) is on another Stage. Switch to it first."; return }
        guard let source = service.display(for: window.hidden == nil ? window.frame : window.realFrame), source.id != target.id else { return }
        let tiledThere = isTabStack(stage: window.stageID, display: target.id) && isLayoutCandidate(window)
        let targetKey = LayoutKey(stage: window.stageID, display: target.id)
        let moved = tiledThere ? joinLayout(id, from: sourceKey, to: targetKey) : moveFreeform(window, from: source, to: target, leaving: sourceKey)
        if moved { notice = "\(window.appName) moved to \(target.name)." }
    }

    private func joinLayout(_ id: UUID, from sourceKey: LayoutKey?, to targetKey: LayoutKey) -> Bool {
        if let sourceKey { leaveLayout(id, sourceKey) }
        var layout = layouts[targetKey] ?? PaneLayout(root: .pane(Pane()))
        let landing = layout.landingPane
        layout.add(id, to: landing)
        if layout.zoomed != landing { layout.zoomed = nil }  // a zoomed neighbour pane would hide the arriving tab
        layouts[targetKey] = layout
        freeformFrames[id] = nil  // it joined this layout later, so leaving TabStack leaves it where it is
        applyLayouts()
        service.focus(id)
        return true
    }

    private func moveFreeform(_ window: LiveWindow, from source: DisplayInfo, to target: DisplayInfo, leaving sourceKey: LayoutKey?) -> Bool {
        let before = snapshot(name: "Before moving window")
        let frame = DisplayRemap.remap(window.hidden == nil ? window.frame : window.realFrame, from: source.area, to: target.area)
        guard service.place(window.id, at: frame) else { error = "\(window.appName) could not be moved to \(target.name)."; return false }
        undoSnapshot = before
        if let sourceKey {
            leaveLayout(window.id, sourceKey)
            freeformFrames[window.id] = nil
            applyLayouts()
        }
        service.focus(window.id)
        publish()
        return true
    }

    /// Takes a window out of a layout; a zoomed pane that empties is un-zoomed so the display is not left blank.
    private func leaveLayout(_ id: UUID, _ key: LayoutKey) {
        guard var layout = layouts[key] else { return }
        layout.remove(id, keepEmptyPanes: state.keepEmptyPanes)
        if let zoomed = layout.zoomed, layout.root.pane(zoomed)?.tabs.isEmpty != false { layout.zoomed = nil }
        layouts[key] = layout
    }
}

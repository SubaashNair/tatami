import AppKit
import TatamiCore

/// Keyboard-only movement between windows: by direction (freeform windows and across displays), and next or previous.
/// Tiled windows keep moving between panes; these take over for freeform windows and where a pane has nothing beyond it.
extension AppModel {
    /// Windows a navigation key can reach: visible, not minimized, on the active Stage (or always visible).
    private func navigableWindows() -> [LiveWindow] {
        // Without management every window is on screen whatever Stage it was assigned, so Stages only matter while managing.
        service.windows.filter { $0.hidden == nil && !$0.minimized && (!managing || isShownOnItsDisplay($0)) }
    }

    private func isTiled(_ id: UUID) -> Bool { layoutKey(containing: id) != nil }

    /// Focus the window in a direction: a pane for a tiled window, otherwise whatever lies that way on screen.
    func focusDirectional(_ direction: Direction) {
        // With no focused window (Finder desktop, a windowless app) pane navigation still works from the display's focused pane.
        if service.focusedID().map(isTiled) ?? true, focusPane(direction) { return }
        focusWindow(direction)
    }

    /// Move the focused window in a direction: to the neighbouring pane if tiled, otherwise swap places with the window there.
    func moveDirectional(_ direction: Direction) {
        if service.focusedID().map(isTiled) ?? true, moveToPane(direction) { return }
        swapWindow(direction)
    }

    private func neighbour(_ direction: Direction) -> (current: LiveWindow, target: LiveWindow)? {
        guard let id = service.focusedID(), let current = service.windows.first(where: { $0.id == id }) else { notice = "Focus a window first."; return nil }
        let others = navigableWindows().filter { $0.id != id }
        guard let targetID = WindowFocus.target(from: current.frame, toward: direction, among: others.map { ($0.id, $0.frame) }),
              let target = others.first(where: { $0.id == targetID }) else { return nil }
        return (current, target)
    }

    func focusWindow(_ direction: Direction) {
        if let pair = neighbour(direction) { service.focus(pair.target.id) }
    }

    func swapWindow(_ direction: Direction) {
        guard let (current, target) = neighbour(direction) else { return }
        guard !isTiled(current.id), !isTiled(target.id) else { notice = "Swapping works between freeform windows."; return }
        let before = snapshot(name: "Before swapping windows")
        guard service.move(current.id, to: target.frame) else {
            _ = service.move(current.id, to: current.frame)  // a refused resize can leave it half moved
            error = "\(current.appName) could not be moved."
            return
        }
        if !service.move(target.id, to: current.frame) {
            _ = service.move(current.id, to: current.frame)  // put it back: half a swap would stack two windows
            error = "\(target.appName) could not be moved, so nothing was swapped."
            return
        }
        undoSnapshot = before  // only a swap that happened replaces the earlier undo
        service.focus(current.id)
        publish()
    }

    /// Next or previous window in reading order across every display, wrapping around.
    func cycleWindows(offset: Int) {
        let order = WindowFocus.readingOrder(navigableWindows().map { (id: $0.id, frame: $0.frame) }, displays: displays.map(\.fullFrame))
        guard let next = WindowFocus.cycle(from: service.focusedID(), offset: offset, in: order) else { notice = "No other window to focus."; return }
        service.focus(next)
    }
}

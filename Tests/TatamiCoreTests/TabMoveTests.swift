import XCTest
@testable import TatamiCore

/// Dragging a tab: reorder it in its pane, or drop it into another pane, in front of a given tab or at the end.
final class TabMoveTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    /// Pane 1 holds a, b, c; pane 2 holds d.
    private func layout() -> (PaneLayout, first: UUID, second: UUID) {
        var layout = PaneLayout(root: .pane(Pane()))
        let first = layout.root.paneIDs[0]
        for window in [a, b, c] { layout.add(window, to: first) }
        let second = layout.split(first, axis: .horizontal, moving: d)!
        return (layout, first, second)
    }

    private func tabs(_ layout: PaneLayout, _ pane: UUID) -> [UUID] { layout.root.pane(pane)?.tabs ?? [] }

    // MARK: reordering inside a pane

    func testATabDroppedOnAnotherTabTakesItsPlaceInFrontOfIt() {
        var (l, first, _) = layout()
        XCTAssertTrue(l.moveTab(c, to: first, before: a, keepEmptyPanes: false))
        XCTAssertEqual(tabs(l, first), [c, a, b])
    }

    func testATabDroppedAtTheEndGoesLast() {
        var (l, first, _) = layout()
        XCTAssertTrue(l.moveTab(a, to: first, before: nil, keepEmptyPanes: false))
        XCTAssertEqual(tabs(l, first), [b, c, a])
    }

    func testDroppingATabWhereItAlreadyIsChangesNothing() {
        var (l, first, _) = layout()
        XCTAssertFalse(l.moveTab(b, to: first, before: c, keepEmptyPanes: false), "already in front of c")
        XCTAssertFalse(l.moveTab(c, to: first, before: nil, keepEmptyPanes: false), "already last")
        XCTAssertFalse(l.moveTab(a, to: first, before: a, keepEmptyPanes: false), "in front of itself")
        XCTAssertEqual(tabs(l, first), [a, b, c])
    }

    // MARK: moving to another pane

    func testATabMovesToAnotherPaneAtTheEndOrInFrontOfATab() {
        var (l, first, second) = layout()
        XCTAssertTrue(l.moveTab(b, to: second, before: nil, keepEmptyPanes: false))
        XCTAssertEqual(tabs(l, first), [a, c])
        XCTAssertEqual(tabs(l, second), [d, b])
        XCTAssertTrue(l.moveTab(c, to: second, before: d, keepEmptyPanes: false))
        XCTAssertEqual(tabs(l, second), [c, d, b])
    }

    func testTheMovedTabIsSelectedAndItsPaneFocused() {
        var (l, first, second) = layout()
        _ = l.moveTab(a, to: second, before: nil, keepEmptyPanes: false)
        XCTAssertEqual(l.root.pane(second)?.selected, a)
        XCTAssertEqual(l.focused, second)
        XCTAssertNotEqual(l.focused, first)
    }

    func testTheSourcePaneKeepsASensibleSelectionAndGoesWhenItEmpties() {
        var (l, first, second) = layout()
        _ = l.moveTab(d, to: first, before: nil, keepEmptyPanes: false)
        XCTAssertNil(l.root.pane(second), "its only tab left, so the pane closed")
        XCTAssertEqual(tabs(l, first), [a, b, c, d])
        var (kept, _, secondKept) = layout()
        _ = kept.moveTab(d, to: kept.root.paneIDs[0], before: nil, keepEmptyPanes: true)
        XCTAssertNotNil(kept.root.pane(secondKept), "an empty pane stays when you keep them")
    }

    func testZoomIsClearedWhenTheZoomedPaneEmpties() {
        var (l, first, second) = layout()
        l.zoomed = second
        _ = l.moveTab(d, to: first, before: nil, keepEmptyPanes: false)
        XCTAssertNil(l.zoomed)
    }

    // MARK: refusals

    func testUnknownTabsPanesAndTargetsChangeNothing() {
        var (l, first, second) = layout()
        let before = l
        XCTAssertFalse(l.moveTab(UUID(), to: first, before: nil, keepEmptyPanes: false), "a tab that is not in this layout")
        XCTAssertFalse(l.moveTab(a, to: UUID(), before: nil, keepEmptyPanes: false), "a pane that does not exist")
        XCTAssertFalse(l.moveTab(a, to: second, before: UUID(), keepEmptyPanes: false), "a target that is not in that pane")
        XCTAssertFalse(l.moveTab(a, to: second, before: b, keepEmptyPanes: false), "a target in another pane")
        XCTAssertEqual(l, before)
    }

    func testMovingTheSelectedTabOutLeavesTheNextMostRecentOneSelected() {
        var (l, first, second) = layout()
        l.select(b); l.select(c)            // most recent first: c, b, a
        _ = l.moveTab(c, to: second, before: nil, keepEmptyPanes: false)
        XCTAssertEqual(l.root.pane(first)?.selected, b, "the tab you used before it")
        XCTAssertEqual(l.root.pane(first)?.mru.first, b)
        XCTAssertFalse(l.root.pane(first)?.mru.contains(c) ?? true)
    }

    func testAPaneWithOneTabDroppedOnItsOwnBarChangesNothing() {
        var (l, _, second) = layout()
        XCTAssertFalse(l.moveTab(d, to: second, before: nil, keepEmptyPanes: false))
        XCTAssertEqual(tabs(l, second), [d])
    }

    func testFocusMovesToTheDestinationWhenTheSourcePaneCloses() {
        var (l, first, second) = layout()
        l.focused = second
        _ = l.moveTab(d, to: first, before: a, keepEmptyPanes: false)
        XCTAssertEqual(l.focused, first, "the pane that closed cannot stay focused")
        XCTAssertEqual(tabs(l, first), [d, a, b, c])
    }
}

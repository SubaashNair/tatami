import XCTest
import CoreGraphics
@testable import TatamiCore

final class PaneLayoutTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 500)

    private func panes(_ layout: PaneLayout) -> [Pane] { layout.root.panes }

    // MARK: building and normalization

    func testBalancedLayoutGivesEachWindowAPaneUpToFour() {
        let layout = PaneLayout.balanced(windows: [a, b, c, d, e], aspect: 2)
        XCTAssertEqual(panes(layout).count, 4)
        XCTAssertEqual(panes(layout).flatMap(\.tabs).sorted { $0.uuidString < $1.uuidString }, [a, b, c, d, e].sorted { $0.uuidString < $1.uuidString })
        XCTAssertEqual(panes(layout).filter { $0.tabs.count == 2 }.count, 1)  // the fifth window joined a pane as a tab
    }

    func testTwoWindowsOnAWideDisplayMakeOneRow() {
        let layout = PaneLayout.balanced(windows: [a, b], aspect: 1.6)
        guard case .split(.horizontal, let children) = layout.root else { return XCTFail("expected a row") }
        XCTAssertEqual(children.count, 2)
    }

    func testSplittingInsideARowAddsASiblingInsteadOfNesting() throws {
        var layout = PaneLayout.balanced(windows: [a, b], aspect: 2)
        let first = panes(layout)[0].id
        let added = try XCTUnwrap(layout.split(first, axis: .horizontal, moving: nil))
        guard case .split(.horizontal, let children) = layout.root else { return XCTFail("expected a flat row") }
        XCTAssertEqual(children.count, 3)
        XCTAssertEqual(children.map(\.weight).reduce(0, +), 2, accuracy: 0.0001)  // the split pane's share was halved
        XCTAssertTrue(layout.root.paneIDs.contains(added))
    }

    func testRemovingTheLastWindowRemovesThePaneAndCollapses() {
        var layout = PaneLayout.balanced(windows: [a, b], aspect: 2)
        layout.remove(b, keepEmptyPanes: false)
        guard case .pane(let pane) = layout.root else { return XCTFail("single child should collapse to a pane") }
        XCTAssertEqual(pane.tabs, [a])
    }

    func testKeepEmptyPanesLeavesAPlaceholder() {
        var layout = PaneLayout.balanced(windows: [a, b], aspect: 2)
        layout.remove(b, keepEmptyPanes: true)
        XCTAssertEqual(panes(layout).count, 2)
    }

    func testLayoutAlwaysKeepsAtLeastOnePane() {
        var layout = PaneLayout.balanced(windows: [a], aspect: 2)
        layout.remove(a, keepEmptyPanes: false)
        XCTAssertEqual(panes(layout).count, 1)
        XCTAssertTrue(panes(layout)[0].tabs.isEmpty)
    }

    // MARK: tabs

    func testMostRecentlyUsedTabIsSelectedWhenTheSelectedOneLeaves() throws {
        var layout = PaneLayout.balanced(windows: [a], aspect: 2)
        let pane = panes(layout)[0].id
        layout.add(b, to: pane); layout.add(c, to: pane)
        layout.select(b); layout.select(c)  // MRU: c, b, a
        layout.remove(c, keepEmptyPanes: false)
        XCTAssertEqual(layout.root.pane(pane)?.selected, b)
    }

    func testCycleTabsWraps() {
        var layout = PaneLayout.balanced(windows: [a], aspect: 2)
        let pane = panes(layout)[0].id
        layout.add(b, to: pane)
        layout.select(b)
        layout.cycleTab(1)
        XCTAssertEqual(layout.root.pane(pane)?.selected, a)
    }

    func testMoveWindowBetweenPanesAndSwap() {
        var layout = PaneLayout.balanced(windows: [a, b], aspect: 2)
        let (left, right) = (panes(layout)[0].id, panes(layout)[1].id)
        layout.move(a, to: right, keepEmptyPanes: true)
        XCTAssertEqual(layout.root.pane(right)?.tabs, [b, a])
        layout.swap(left, right)
        XCTAssertEqual(layout.root.pane(left)?.tabs, [b, a])
    }

    // MARK: geometry

    func testFramesWithGapsAndTabBars() {
        let layout = PaneLayout.balanced(windows: [a, b], aspect: 2)
        let frames = layout.frames(in: area, gap: 10, tabBar: 28)
        let (left, right) = (panes(layout)[0].id, panes(layout)[1].id)
        XCTAssertEqual(frames[left]?.pane, CGRect(x: 10, y: 10, width: 485, height: 480))
        XCTAssertEqual(frames[right]?.pane, CGRect(x: 505, y: 10, width: 485, height: 480))
        XCTAssertEqual(frames[left]?.window, CGRect(x: 10, y: 38, width: 485, height: 452))
    }

    func testZoomGivesOnePaneTheWholeArea() {
        var layout = PaneLayout.balanced(windows: [a, b], aspect: 2)
        let left = panes(layout)[0].id
        layout.toggleZoom(left)
        let frames = layout.frames(in: area, gap: 0, tabBar: 0)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[left]?.pane, area)
    }

    func testNeighboursFollowGeometryAcrossDisplays() {
        let candidates: [(UUID, CGRect)] = [(a, CGRect(x: 0, y: 0, width: 500, height: 500)), (b, CGRect(x: 500, y: 0, width: 500, height: 250)),
                                            (c, CGRect(x: 500, y: 250, width: 500, height: 250)), (d, CGRect(x: 1000, y: 0, width: 800, height: 500))]
        XCTAssertEqual(PaneLayout.neighbour(of: CGRect(x: 0, y: 0, width: 500, height: 500), toward: .right, among: candidates), b)
        XCTAssertEqual(PaneLayout.neighbour(of: candidates[1].1, toward: .down, among: candidates), c)
        XCTAssertEqual(PaneLayout.neighbour(of: candidates[2].1, toward: .right, among: candidates), d)  // next display
        XCTAssertNil(PaneLayout.neighbour(of: candidates[0].1, toward: .left, among: candidates))
    }

    func testEdgeDragChangesOnlyTheAdjacentPanes() throws {
        var layout = PaneLayout.balanced(windows: [a, b, c], aspect: 3)  // one row of three
        let ids = panes(layout).map(\.id)
        let before = layout.frames(in: area, gap: 0, tabBar: 0)
        var dragged = try XCTUnwrap(before[ids[0]]).window
        dragged.size.width += 100
        layout.applyEdgeDrag(pane: ids[0], expected: before[ids[0]]!.window, actual: dragged, in: area, gap: 0, tabBar: 0)
        let after = layout.frames(in: area, gap: 0, tabBar: 0)
        XCTAssertEqual(after[ids[0]]!.pane.width, before[ids[0]]!.pane.width + 100, accuracy: 1)
        XCTAssertEqual(after[ids[1]]!.pane.width, before[ids[1]]!.pane.width - 100, accuracy: 1)
        XCTAssertEqual(after[ids[2]]!.pane.width, before[ids[2]]!.pane.width, accuracy: 1)  // untouched
    }

    func testResizeGrowsFocusedPaneAtNeighbourExpense() {
        var layout = PaneLayout.balanced(windows: [a, b], aspect: 2)
        let left = panes(layout)[0].id
        layout.resize(left, by: 0.1)
        let frames = layout.frames(in: area, gap: 0, tabBar: 0)
        XCTAssertEqual(frames[left]!.pane.width, 600, accuracy: 1)
    }

    func testEvenOutAndReflow() {
        var layout = PaneLayout.balanced(windows: [a, b], aspect: 2)
        let left = panes(layout)[0].id
        layout.resize(left, by: 0.2)
        layout.evenOut()
        XCTAssertEqual(layout.frames(in: area, gap: 0, tabBar: 0)[left]!.pane.width, 500, accuracy: 1)
        _ = layout.split(left, axis: .vertical, moving: nil)
        _ = layout.split(left, axis: .vertical, moving: nil)
        layout.reflow(aspect: 2)
        let widths = Set(layout.frames(in: area, gap: 0, tabBar: 0).values.map { Int($0.pane.width) })
        XCTAssertEqual(widths, [500])  // four panes as a 2 × 2 grid
    }

    // MARK: placement and undo

    func testAutomaticPlacementSplitsUntilFourPanesThenTabs() {
        var layout = PaneLayout.balanced(windows: [a], aspect: 2)
        for window in [b, c, d] { layout.place(window, policy: .automatic, in: area) }
        XCTAssertEqual(panes(layout).count, 4)
        layout.place(e, policy: .automatic, in: area)
        XCTAssertEqual(panes(layout).count, 4)
        XCTAssertEqual(layout.root.pane(layout.focused)?.tabs.last, e)
    }

    func testActivePlacementAlwaysTabs() {
        var layout = PaneLayout.balanced(windows: [a], aspect: 2)
        layout.place(b, policy: .active, in: area)
        XCTAssertEqual(panes(layout).count, 1)
        XCTAssertEqual(panes(layout)[0].selected, b)
    }

    func testUndoHistoryIsBounded() {
        var history = LayoutHistory(limit: 3)
        let layout = PaneLayout.balanced(windows: [a], aspect: 2)
        for _ in 0..<5 { history.record(layout) }
        XCTAssertEqual(history.count, 3)
        XCTAssertNotNil(history.undo())
    }

    func testCodableRoundTrip() throws {
        var layout = PaneLayout.balanced(windows: [a, b, c], aspect: 1.2)
        layout.toggleZoom(panes(layout)[1].id)
        let decoded = try JSONDecoder().decode(PaneLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(decoded, layout)
    }
}

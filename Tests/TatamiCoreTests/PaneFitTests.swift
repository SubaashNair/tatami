import XCTest
import CoreGraphics
@testable import TatamiCore

/// A window that cannot shrink below some size makes its pane grow, taking space from neighbours, instead of spilling over them.
final class PaneFitTests: XCTestCase {
    private let a = UUID(), b = UUID()
    private let area = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    private let gap = 12.0, bar = 28.0

    private func sideBySide() -> (layout: PaneLayout, left: UUID, right: UUID) {
        var layout = PaneLayout(root: .pane(Pane(tabs: [a])))
        let left = layout.focused
        let right = layout.split(left, axis: .horizontal, moving: b)!
        return (layout, left, right)
    }

    private func windowRect(_ layout: PaneLayout, _ pane: UUID) -> CGRect {
        layout.frames(in: area, gap: gap, tabBar: bar)[pane]!.window
    }

    func testAPaneGrowsToHoldAWideWindow() {
        let (initial, left, right) = sideBySide()
        var layout = initial
        XCTAssertLessThan(windowRect(layout, right).width, 900)  // equal halves of 1600 are too narrow
        XCTAssertTrue(layout.fit(right, toWindowSize: CGSize(width: 900, height: 400), in: area, gap: gap, tabBar: bar))
        XCTAssertGreaterThanOrEqual(windowRect(layout, right).width, 899)
        XCTAssertLessThan(windowRect(layout, left).width, windowRect(layout, right).width)  // the neighbour gave way
    }

    func testAPaneGrowsToHoldATallWindow() {
        var layout = PaneLayout(root: .pane(Pane(tabs: [a])))
        let top = layout.focused
        let bottom = layout.split(top, axis: .vertical, moving: b)!
        XCTAssertTrue(layout.fit(bottom, toWindowSize: CGSize(width: 400, height: 700), in: area, gap: gap, tabBar: bar))
        XCTAssertGreaterThanOrEqual(windowRect(layout, bottom).height, 699)
        XCTAssertLessThan(windowRect(layout, top).height, windowRect(layout, bottom).height)
    }

    func testNothingChangesWhenTheWindowAlreadyFits() {
        let (initial, left, _) = sideBySide()
        var layout = initial
        XCTAssertTrue(layout.fit(left, toWindowSize: CGSize(width: 300, height: 300), in: area, gap: gap, tabBar: bar))
        XCTAssertEqual(layout, initial)
    }

    func testItReportsFailureAndChangesNothingWhenNoRoomCanBeMade() {
        let (initial, _, right) = sideBySide()
        var layout = initial
        // The neighbour keeps a minimum share, so a window nearly as wide as the screen cannot fit.
        XCTAssertFalse(layout.fit(right, toWindowSize: CGSize(width: 1580, height: 400), in: area, gap: gap, tabBar: bar))
        XCTAssertEqual(layout, initial)
    }

    func testAWindowBiggerThanTheScreenCannotFit() {
        var layout = PaneLayout(root: .pane(Pane(tabs: [a])))
        let only = layout.focused
        let before = layout
        XCTAssertFalse(layout.fit(only, toWindowSize: CGSize(width: 3000, height: 400), in: area, gap: gap, tabBar: bar))
        XCTAssertEqual(layout, before)
    }

    func testGrowingKeepsEveryWindowInItsPane() {
        let (initial, left, right) = sideBySide()
        var layout = initial
        _ = layout.fit(right, toWindowSize: CGSize(width: 900, height: 400), in: area, gap: gap, tabBar: bar)
        XCTAssertEqual(layout.root.pane(left)?.tabs, [a])
        XCTAssertEqual(layout.root.pane(right)?.tabs, [b])
        XCTAssertEqual(layout.root.paneIDs, initial.root.paneIDs)
    }

    func testAMiddlePaneTakesSpaceFromBothSides() {
        // A | B | C on 1600: B needs 900, which is only possible if A and C both give way (one side alone would drop below 240).
        var layout = PaneLayout(root: .pane(Pane(tabs: [a])))
        let first = layout.focused
        let middle = layout.split(first, axis: .horizontal, moving: b)!
        let last = layout.split(middle, axis: .horizontal, moving: UUID())!
        XCTAssertTrue(layout.fit(middle, toWindowSize: CGSize(width: 900, height: 400), in: area, gap: gap, tabBar: bar))
        XCTAssertGreaterThanOrEqual(windowRect(layout, middle).width, 899)
        for pane in [first, last] { XCTAssertGreaterThanOrEqual(layout.frames(in: area, gap: gap, tabBar: bar)[pane]!.pane.width, 240) }
    }

    func testAPaneThatWasAlreadySmallDoesNotBlockTheFit() {
        // C is already narrow and is not touched by growing A at B's expense, so it must not veto the change.
        var layout = PaneLayout(root: .pane(Pane(tabs: [a])))
        let first = layout.focused
        let middle = layout.split(first, axis: .horizontal, moving: b)!
        let last = layout.split(middle, axis: .horizontal, moving: UUID())!
        layout.resize(middle, by: 0.3)  // squeezes C
        XCTAssertLessThan(layout.frames(in: area, gap: gap, tabBar: bar)[last]!.pane.width, 240)
        XCTAssertTrue(layout.fit(first, toWindowSize: CGSize(width: 650, height: 300), in: area, gap: gap, tabBar: bar))
    }

    func testItDoesNotShrinkAnotherPaneBelowItsOwnKnownMinimum() {
        let (initial, left, right) = sideBySide()
        var layout = initial
        // The left window cannot go below 1000 wide and the right one wants 1000 too. Both cannot fit on 1600.
        XCTAssertFalse(layout.fit(right, toWindowSize: CGSize(width: 1000, height: 300), in: area, gap: gap, tabBar: bar, keeping: [left: CGSize(width: 1000, height: 300)]))
        XCTAssertEqual(layout, initial)
        // Without that knowledge the same request succeeds.
        var other = initial
        XCTAssertTrue(other.fit(right, toWindowSize: CGSize(width: 1000, height: 300), in: area, gap: gap, tabBar: bar))
    }

    func testANestedPaneGrowsInBothDirections() {
        // A | (B over C): C needs to be wider than its column and taller than its half.
        var layout = PaneLayout(root: .pane(Pane(tabs: [a])))
        let first = layout.focused
        let second = layout.split(first, axis: .horizontal, moving: b)!
        let third = layout.split(second, axis: .vertical, moving: UUID())!
        XCTAssertTrue(layout.fit(third, toWindowSize: CGSize(width: 1000, height: 600), in: area, gap: gap, tabBar: bar))
        let grown = windowRect(layout, third)
        XCTAssertGreaterThanOrEqual(grown.width, 999)
        XCTAssertGreaterThanOrEqual(grown.height, 599)
    }
}

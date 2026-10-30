import XCTest
import CoreGraphics
@testable import TatamiCore

/// Rotating a split: side by side becomes stacked and back, without moving windows between panes.
final class PaneRotateTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 500)

    private func twoPanes() -> (layout: PaneLayout, first: UUID, second: UUID) {
        var layout = PaneLayout(root: .pane(Pane(tabs: [a])))
        let first = layout.focused
        let second = layout.split(first, axis: .horizontal, moving: b)!
        return (layout, first, second)
    }

    func testSideBySideBecomesStackedAndKeepsTheOrder() throws {
        let (initial, first, second) = twoPanes()
        var layout = initial
        layout.rotateSplit(of: second)
        guard case .split(.vertical, let children) = layout.root else { return XCTFail("expected a column") }
        XCTAssertEqual(children.map { $0.node.paneIDs }, [[first], [second]])
        let frames = layout.root.rects(in: area)
        XCTAssertLessThan(try XCTUnwrap(frames[first]).minY, try XCTUnwrap(frames[second]).minY)  // first is now on top
    }

    func testRotatingTwiceRestoresTheLayout() {
        let (initial, _, second) = twoPanes()
        var layout = initial
        layout.rotateSplit(of: second)
        layout.rotateSplit(of: second)
        XCTAssertEqual(layout, initial)
    }

    func testRotatingKeepsEveryWindowInItsPane() {
        let (initial, first, second) = twoPanes()
        var layout = initial
        layout.rotateSplit(of: first)
        XCTAssertEqual(layout.root.pane(first)?.tabs, [a])
        XCTAssertEqual(layout.root.pane(second)?.tabs, [b])
    }

    func testOnlyTheFocusedPanesSplitRotates() {
        // A | (B over C): rotating B and C's column gives A | B | C, so the outer row is untouched and absorbs them.
        let (initial, _, second) = twoPanes()
        var layout = initial
        let third = layout.split(second, axis: .vertical, moving: c)!
        layout.rotateSplit(of: third)
        guard case .split(.horizontal, let children) = layout.root else { return XCTFail("expected one row") }
        XCTAssertEqual(children.count, 3)
        XCTAssertEqual(layout.root.panes.flatMap(\.tabs), [a, b, c])
    }

    func testWeightsSurviveRotation() throws {
        let (initial, first, second) = twoPanes()
        var layout = initial
        layout.resize(first, by: 0.2)
        let before = layout.root.rects(in: area)
        layout.rotateSplit(of: second)
        let after = layout.root.rects(in: CGRect(x: 0, y: 0, width: 500, height: 1000))
        let shareBefore = try XCTUnwrap(before[first]).width / 1000
        let shareAfter = try XCTUnwrap(after[first]).height / 1000
        XCTAssertEqual(shareBefore, shareAfter, accuracy: 0.001)
    }

    func testAlonePaneHasNothingToRotate() {
        var layout = PaneLayout(root: .pane(Pane(tabs: [a])))
        let original = layout
        layout.rotateSplit(of: layout.focused)
        XCTAssertEqual(layout, original)
    }

    func testAnUnknownPaneChangesNothing() {
        let (initial, _, _) = twoPanes()
        var layout = initial
        layout.rotateSplit(of: UUID())
        XCTAssertEqual(layout, initial)
    }
}

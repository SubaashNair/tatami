import XCTest
import CoreGraphics
@testable import TatamiCore

final class DisplayMoveTests: XCTestCase {
    private let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    private let below = CGRect(x: 0, y: 900, width: 1440, height: 900)

    // MARK: next and previous display

    func testNextDisplayFollowsLeftToRightOrderAndWraps() {
        let displays = [("right", right), ("left", left)]  // input order must not matter
        XCTAssertEqual(DisplayOrder.neighbour(of: "left", offset: 1, in: displays), "right")
        XCTAssertEqual(DisplayOrder.neighbour(of: "right", offset: 1, in: displays), "left")
        XCTAssertEqual(DisplayOrder.neighbour(of: "left", offset: -1, in: displays), "right")
    }

    func testStackedDisplaysOrderTopToBottomWhenLeftEdgesMatch() {
        let displays = [("below", below), ("left", left), ("right", right)]
        XCTAssertEqual(DisplayOrder.neighbour(of: "left", offset: 1, in: displays), "below")
        XCTAssertEqual(DisplayOrder.neighbour(of: "below", offset: 1, in: displays), "right")
        XCTAssertEqual(DisplayOrder.neighbour(of: "right", offset: -1, in: displays), "below")
    }

    func testOneDisplayOrUnknownCurrentHasNoNeighbour() {
        XCTAssertNil(DisplayOrder.neighbour(of: "left", offset: 1, in: [("left", left)]))
        XCTAssertNil(DisplayOrder.neighbour(of: "missing", offset: 1, in: [("left", left), ("right", right)]))
        XCTAssertNil(DisplayOrder.neighbour(of: "left", offset: 1, in: [(String, CGRect)]()))
    }

    func testOffsetLargerThanTheDisplayCountStillWraps() {
        let displays = [("left", left), ("right", right)]
        XCTAssertEqual(DisplayOrder.neighbour(of: "left", offset: 3, in: displays), "right")
        XCTAssertEqual(DisplayOrder.neighbour(of: "left", offset: -3, in: displays), "right")
    }

    func testOrderedListsDisplaysLeftToRightThenTopToBottom() {
        XCTAssertEqual(DisplayOrder.ordered([("below", below), ("right", right), ("left", left)]), ["left", "below", "right"])
    }

    // MARK: where a window lands in a display's layout

    func testLandingPaneIsTheFocusedPane() {
        var layout = PaneLayout(root: .pane(Pane(tabs: [UUID()])))
        let second = layout.split(layout.focused, axis: .horizontal, moving: nil)!
        layout.focused = second
        XCTAssertEqual(layout.landingPane, second)
    }

    func testLandingPaneFallsBackToTheFirstPaneWhenFocusIsStale() {
        var layout = PaneLayout(root: .pane(Pane(tabs: [UUID()])))
        let first = layout.root.panes[0].id
        layout.focused = UUID()
        XCTAssertEqual(layout.landingPane, first)
    }

    func testAddingToTheLandingPaneMakesTheWindowATab() {
        let existing = UUID(), incoming = UUID()
        var layout = PaneLayout(root: .pane(Pane(tabs: [existing])))
        layout.add(incoming, to: layout.landingPane)
        XCTAssertEqual(layout.root.panes[0].tabs, [existing, incoming])
        XCTAssertEqual(layout.root.panes[0].selected, incoming)
    }
}

import XCTest
@testable import TatamiCore

/// A window that fills its display (maximized with the green button) is a zoomed pane, not a window to float or snap back.
final class WindowCoverageTests: XCTestCase {
    private let area = CGRect(x: 0, y: 38, width: 2000, height: 1200)

    func testAWindowThatFillsTheWholeAreaFillsTheDisplay() {
        XCTAssertTrue(WindowCoverage.fillsDisplay(area, area: area))
    }

    func testAWindowAFewPointsShortStillCountsAsMaximized() {
        XCTAssertTrue(WindowCoverage.fillsDisplay(CGRect(x: 4, y: 40, width: 1992, height: 1190), area: area))
    }

    func testATiledPaneDoesNotFillTheDisplay() {
        XCTAssertFalse(WindowCoverage.fillsDisplay(CGRect(x: 6, y: 80, width: 980, height: 1150), area: area))
        XCTAssertFalse(WindowCoverage.fillsDisplay(CGRect(x: 0, y: 38, width: 2000, height: 600), area: area), "full width but half the height")
    }

    func testOnlyThePartInsideTheDisplayCounts() {
        let spilling = CGRect(x: -500, y: 38, width: 3000, height: 1200)  // wider than the display but mostly on it
        XCTAssertTrue(WindowCoverage.fillsDisplay(spilling, area: area))
        let elsewhere = CGRect(x: 2100, y: 38, width: 2000, height: 1200)  // on the next display
        XCTAssertFalse(WindowCoverage.fillsDisplay(elsewhere, area: area))
    }

    func testAZoomedPaneItselfIsNotMistakenForAMaximizedWindow() {
        // Tatami's own zoomed pane leaves room for the tab bar and a gap, so it never re-triggers the check.
        let zoomedPane = CGRect(x: 6, y: 38 + 6 + 28, width: 1988, height: 1200 - 12 - 28)
        XCTAssertFalse(WindowCoverage.fillsDisplay(zoomedPane, area: area))
    }

    func testAMaximizedWindowOnlyStopsCountingOnceItIsClearlySmaller() {
        let zoomedPane = CGRect(x: 6, y: 72, width: 1988, height: 1160)
        XCTAssertTrue(WindowCoverage.stillFills(zoomedPane, area: area), "Tatami's own zoomed frame stays zoomed")
        XCTAssertTrue(WindowCoverage.stillFills(CGRect(x: 100, y: 100, width: 1800, height: 1100), area: area), "a bit smaller: still zoomed")
        XCTAssertFalse(WindowCoverage.stillFills(CGRect(x: 100, y: 100, width: 1000, height: 700), area: area), "the user shrank it")
    }

    func testAnEmptyAreaIsNeverFilled() {
        XCTAssertFalse(WindowCoverage.fillsDisplay(area, area: .zero))
        XCTAssertFalse(WindowCoverage.stillFills(area, area: .zero))
    }

    func testTatamisOwnZoomedPaneNeverLooksMaximizedWhateverTheGapOrDisplay() {
        let areas = [CGRect(x: 0, y: 38, width: 2000, height: 1200), CGRect(x: 0, y: 25, width: 1080, height: 1895), CGRect(x: 0, y: 25, width: 3440, height: 1415)]
        let first = UUID(), second = UUID()
        for area in areas {
            for gap in [0.0, 4, 12, 40] {
                var layout = PaneLayout(root: .pane(Pane()))
                layout.add(first, to: layout.root.paneIDs[0])
                let split = layout.split(layout.focused, axis: .horizontal, moving: second)
                layout.zoomed = split
                guard let frame = layout.frames(in: area, gap: gap, tabBar: 28)[split!]?.window else { return XCTFail("no frame") }
                XCTAssertFalse(WindowCoverage.fillsDisplay(frame, area: area), "gap \(gap) on \(area.size)")
            }
        }
    }

    // MARK: what to do about a window that fills the display

    private let tile = CGRect(x: 6, y: 80, width: 980, height: 1150)

    func testAWindowThatGrewToFillTheDisplayZoomsItsPane() {
        XCTAssertEqual(MaximizeRules.action(isZoomed: false, zoomedByUs: false, frame: area, expected: tile, area: area, justLeftFullScreen: false), .zoom)
    }

    func testAWindowWeNeverPlacedIsNotJudged() {
        XCTAssertEqual(MaximizeRules.action(isZoomed: false, zoomedByUs: false, frame: area, expected: nil, area: area, justLeftFullScreen: false), .none,
                       "a new window that opened big is placed first, not zoomed")
    }

    func testAWindowWeAskedToFillTheDisplayIsLeftAlone() {
        XCTAssertEqual(MaximizeRules.action(isZoomed: false, zoomedByUs: false, frame: area, expected: area, area: area, justLeftFullScreen: false), .none)
    }

    func testAFullScreenExitInProgressIsNeverZoomed() {
        XCTAssertEqual(MaximizeRules.action(isZoomed: false, zoomedByUs: false, frame: area, expected: tile, area: area, justLeftFullScreen: true), .none)
    }

    func testOnlyAZoomWeStartedIsUndoneAndOnlyWhenTheWindowIsClearlySmaller() {
        let small = CGRect(x: 100, y: 100, width: 900, height: 600)
        XCTAssertEqual(MaximizeRules.action(isZoomed: true, zoomedByUs: true, frame: small, expected: area, area: area, justLeftFullScreen: false), .unzoom)
        XCTAssertEqual(MaximizeRules.action(isZoomed: true, zoomedByUs: false, frame: small, expected: area, area: area, justLeftFullScreen: false), .none,
                       "a pane you zoomed with the key stays zoomed")
        XCTAssertEqual(MaximizeRules.action(isZoomed: true, zoomedByUs: true, frame: CGRect(x: 6, y: 72, width: 1988, height: 1160), expected: area, area: area, justLeftFullScreen: false), .none)
    }
}

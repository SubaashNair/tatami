import XCTest
import CoreGraphics
@testable import TatamiCore

final class WindowFocusTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    private let second = CGRect(x: 1600, y: 0, width: 1600, height: 1000)

    // Snapped layouts, as the snap shortcuts produce them.
    private let leftHalf = CGRect(x: 0, y: 0, width: 800, height: 1000)
    private let rightHalf = CGRect(x: 800, y: 0, width: 800, height: 1000)
    private let topLeft = CGRect(x: 0, y: 0, width: 800, height: 500)
    private let topRight = CGRect(x: 800, y: 0, width: 800, height: 500)
    private let bottomLeft = CGRect(x: 0, y: 500, width: 800, height: 500)
    private let bottomRight = CGRect(x: 800, y: 500, width: 800, height: 500)

    // MARK: directional focus

    func testSnappedHalvesFocusEachOtherAndStopAtTheEdge() {
        let others = [("right", rightHalf)]
        XCTAssertEqual(WindowFocus.target(from: leftHalf, toward: .right, among: others), "right")
        XCTAssertNil(WindowFocus.target(from: leftHalf, toward: .left, among: others))
        XCTAssertNil(WindowFocus.target(from: leftHalf, toward: .up, among: others))
        XCTAssertNil(WindowFocus.target(from: leftHalf, toward: .down, among: others))
    }

    func testQuartersMoveAlongRowsAndColumns() {
        let others = [("tr", topRight), ("bl", bottomLeft), ("br", bottomRight)]
        XCTAssertEqual(WindowFocus.target(from: topLeft, toward: .right, among: others), "tr")
        XCTAssertEqual(WindowFocus.target(from: topLeft, toward: .down, among: others), "bl")
        XCTAssertEqual(WindowFocus.target(from: bottomRight, toward: .up, among: others), "tr")
        XCTAssertEqual(WindowFocus.target(from: bottomRight, toward: .left, among: others), "bl")
    }

    func testAlignedNeighbourBeatsANearerMisalignedOne() {
        // Both touch the left window's right edge; the one sharing more of its height wins over a small one low down.
        let near = CGRect(x: 800, y: 0, width: 400, height: 500)
        let farBelow = CGRect(x: 800, y: 900, width: 100, height: 80)
        XCTAssertEqual(WindowFocus.target(from: leftHalf, toward: .right, among: [("far", farBelow), ("near", near)]), "near")
    }

    func testFocusCrossesToTheNextDisplay() {
        let onSecond = CGRect(x: 1700, y: 100, width: 900, height: 700)
        XCTAssertEqual(WindowFocus.target(from: rightHalf, toward: .right, among: [("second", onSecond)]), "second")
        XCTAssertEqual(WindowFocus.target(from: onSecond, toward: .left, among: [("first", rightHalf)]), "first")
    }

    func testOverlappingWindowsStillHaveADirection() {
        // Cascaded freeform windows overlap, so none sits strictly beside another.
        let a = CGRect(x: 100, y: 100, width: 600, height: 400)
        let b = CGRect(x: 300, y: 200, width: 600, height: 400)
        XCTAssertEqual(WindowFocus.target(from: a, toward: .right, among: [("b", b)]), "b")
        XCTAssertEqual(WindowFocus.target(from: a, toward: .down, among: [("b", b)]), "b")
        XCTAssertNil(WindowFocus.target(from: a, toward: .left, among: [("b", b)]))
        XCTAssertNil(WindowFocus.target(from: a, toward: .up, among: [("b", b)]))
    }

    func testAnOverlappingWindowBeatsAFarAwayOneBesideIt() {
        // B overlaps A, so it is the natural next window to the right; C is strictly beside A but far off.
        let a = CGRect(x: 100, y: 100, width: 400, height: 400)
        let b = CGRect(x: 400, y: 150, width: 400, height: 400)
        let c = CGRect(x: 1500, y: 100, width: 400, height: 400)
        XCTAssertEqual(WindowFocus.target(from: a, toward: .right, among: [("c", c), ("b", b)]), "b")
    }

    func testTouchingWindowsAreStillBesideEachOther() {
        // Snapped halves share an edge but do not overlap, so the strict neighbour rule still applies.
        let far = CGRect(x: 1700, y: 0, width: 400, height: 1000)
        XCTAssertEqual(WindowFocus.target(from: leftHalf, toward: .right, among: [("far", far), ("half", rightHalf)]), "half")
    }

    func testNoCandidatesMeansNoTarget() {
        XCTAssertNil(WindowFocus.target(from: leftHalf, toward: .right, among: [(String, CGRect)]()))
    }

    // MARK: next and previous window

    func testReadingOrderGoesAcrossDisplaysThenDownThenAcross() {
        let windows = [(id: "c", frame: bottomLeft),
                       (id: "x", frame: CGRect(x: 1700, y: 50, width: 800, height: 600)),
                       (id: "b", frame: topRight),
                       (id: "a", frame: topLeft)]
        XCTAssertEqual(WindowFocus.readingOrder(windows, displays: [second, screen]), ["a", "b", "c", "x"])
    }

    func testWindowsOnTheSameRowStayLeftToRightDespiteAFewPointsOffset() {
        // Side by side, but the left window's top edge is 2 pt lower than the right one's.
        let left = CGRect(x: 0, y: 2, width: 800, height: 998)
        let right = CGRect(x: 800, y: 0, width: 800, height: 1000)
        XCTAssertEqual(WindowFocus.readingOrder([(id: "right", frame: right), (id: "left", frame: left)], displays: [screen]), ["left", "right"])
    }

    func testCycleWrapsInBothDirections() {
        let order = ["a", "b", "c"]
        XCTAssertEqual(WindowFocus.cycle(from: "a", offset: 1, in: order), "b")
        XCTAssertEqual(WindowFocus.cycle(from: "c", offset: 1, in: order), "a")
        XCTAssertEqual(WindowFocus.cycle(from: "a", offset: -1, in: order), "c")
    }

    func testCycleWithoutAFocusedWindowStartsAtAnEnd() {
        let order = ["a", "b", "c"]
        XCTAssertEqual(WindowFocus.cycle(from: nil, offset: 1, in: order), "a")
        XCTAssertEqual(WindowFocus.cycle(from: nil, offset: -1, in: order), "c")
        XCTAssertEqual(WindowFocus.cycle(from: "gone", offset: 1, in: order), "a")
    }

    func testCycleHasNothingToDoWithFewerThanTwoWindows() {
        XCTAssertNil(WindowFocus.cycle(from: "a", offset: 1, in: ["a"]))
        XCTAssertNil(WindowFocus.cycle(from: nil, offset: 1, in: [String]()))
    }
}

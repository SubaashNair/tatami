import XCTest
import CoreGraphics
@testable import TatamiCore

final class EngineTests: XCTestCase {
    // AX coordinates: origin top-left of the primary display, y grows downward.
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let right = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
    private let below = CGRect(x: 0, y: 982, width: 1512, height: 982)
    private let window = CGSize(width: 800, height: 600)

    // MARK: display identity

    private func display(_ vendor: UInt32, _ model: UInt32, _ serial: UInt32, x: Double, y: Double = 0, uuid: String = UUID().uuidString) -> DisplayFingerprint {
        DisplayFingerprint(vendor: vendor, model: model, serial: serial, uuid: uuid, frame: CGRect(x: x, y: y, width: 1920, height: 1080))
    }

    func testUniqueHardwareKeysSurvivePortSwapAndResolutionChange() {
        let before = [display(1, 2, 100, x: 0, uuid: "A"), display(3, 4, 200, x: 1920, uuid: "B")]
        var after = [display(3, 4, 200, x: 0, uuid: "C"), display(1, 2, 100, x: 1920, uuid: "D")]
        after[1].frame.size = CGSize(width: 2560, height: 1440)
        XCTAssertEqual(Set(DisplayFingerprint.keys(for: before)), Set(DisplayFingerprint.keys(for: after)))
        XCTAssertEqual(DisplayFingerprint.keys(for: before)[0], DisplayFingerprint.keys(for: after)[1])
    }

    func testIdenticalMonitorsAreDisambiguatedByArrangement() {
        let twins = [display(5, 6, 0, x: 1920), display(5, 6, 0, x: 0)]
        let keys = DisplayFingerprint.keys(for: twins)
        XCTAssertEqual(Set(keys).count, 2)
        XCTAssertEqual(keys[1], "5-6-0#0")  // leftmost first
        XCTAssertEqual(keys[0], "5-6-0#1")
    }

    func testUnknownHardwareFallsBackToUUID() {
        XCTAssertEqual(DisplayFingerprint.keys(for: [display(0, 0, 0, x: 0, uuid: "XYZ")]), ["uuid-XYZ"])
    }

    // MARK: parking

    func testParksAtBottomRightOfSingleDisplay() {
        let parked = ParkPlanner.parkFrame(size: window, display: laptop, others: [])!
        XCTAssertEqual(parked.origin, CGPoint(x: laptop.maxX - ParkPlanner.sliver, y: laptop.maxY - ParkPlanner.sliver))
        XCTAssertTrue(ParkPlanner.isParked(parked, displays: [laptop]))
    }

    func testAvoidsNeighbourToTheRight() {
        let parked = ParkPlanner.parkFrame(size: window, display: laptop, others: [right])!
        XCTAssertLessThan(parked.minX, laptop.minX)  // bottom-left instead
        XCTAssertFalse(parked.intersects(right))
    }

    func testReturnsNilWhenBothBottomCornersAreBlocked() {
        let wideBelow = CGRect(x: -500, y: 982, width: 2600, height: 982)
        XCTAssertNil(ParkPlanner.parkFrame(size: window, display: laptop, others: [wideBelow]))
    }

    func testNarrowerDisplayBelowLeavesCornerFree() {
        let external = CGRect(x: -500, y: -1440, width: 2560, height: 1440)
        let parked = ParkPlanner.parkFrame(size: window, display: external, others: [laptop])!
        XCTAssertFalse(parked.intersects(laptop))
    }

    func testParkZoneDetection() {
        XCTAssertFalse(ParkPlanner.isParked(CGRect(x: 100, y: 100, width: 800, height: 600), displays: [laptop]))
        XCTAssertFalse(ParkPlanner.isParked(CGRect(x: 1200, y: 700, width: 800, height: 600), displays: [laptop])) // partly visible, not parked
        XCTAssertTrue(ParkPlanner.isParked(CGRect(x: 5000, y: 5000, width: 800, height: 600), displays: [laptop]))
    }

    // MARK: remap

    func testProportionalRemapKeepsRelativePlacement() {
        let leftHalf = CGRect(x: 1512, y: 0, width: 1280, height: 1440)
        let mapped = DisplayRemap.remap(leftHalf, from: right, to: laptop)
        XCTAssertEqual(mapped, CGRect(x: 0, y: 0, width: 756, height: 982))
    }

    func testRemapClampsIntoDestination() {
        let mapped = DisplayRemap.remap(CGRect(x: 4000, y: 1400, width: 100, height: 100), from: right, to: laptop)
        XCTAssertTrue(laptop.contains(mapped))
    }

    // MARK: checkpoint matching

    private let stage = UUID()
    private func saved(_ number: UInt32?, pid: Int32 = 10, bundle: String = "app", title: String) -> CheckpointWindow {
        CheckpointWindow(windowNumber: number, pid: pid, bundleID: bundle, title: title, frame: Rect(CGRect(x: 0, y: 0, width: 10, height: 10)), stageID: stage, displayKey: nil)
    }

    func testMatchesByWindowNumberDespiteTitleChange() {
        let live = [LiveWindowKey(windowNumber: 7, pid: 10, bundleID: "app", title: "New title")]
        XCTAssertEqual(CheckpointWindow.match(saved: [saved(7, title: "Old title")], live: live), [0: 0])
    }

    func testDuplicateTitlesMatchInOrderAfterAppRelaunch() {
        let savedWindows = [saved(1, title: "Untitled"), saved(2, title: "Untitled"), saved(3, title: "Other")]
        let live = [LiveWindowKey(windowNumber: 50, pid: 99, bundleID: "app", title: "Other"),
                    LiveWindowKey(windowNumber: 51, pid: 99, bundleID: "app", title: "Untitled"),
                    LiveWindowKey(windowNumber: 52, pid: 99, bundleID: "app", title: "Untitled")]
        XCTAssertEqual(CheckpointWindow.match(saved: savedWindows, live: live), [0: 1, 1: 2, 2: 0])
    }

    func testWindowNumberFromAnotherProcessDoesNotMatch() {
        let live = [LiveWindowKey(windowNumber: 7, pid: 11, bundleID: "other", title: "x")]
        XCTAssertTrue(CheckpointWindow.match(saved: [saved(7, title: "y")], live: live).isEmpty)
    }

    func testEachLiveWindowMatchesAtMostOnce() {
        let live = [LiveWindowKey(windowNumber: 7, pid: 10, bundleID: "app", title: "Doc")]
        let result = CheckpointWindow.match(saved: [saved(7, title: "Doc"), saved(8, title: "Doc")], live: live)
        XCTAssertEqual(result, [0: 0])
    }
}

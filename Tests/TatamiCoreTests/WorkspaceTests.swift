import XCTest
import CoreGraphics
@testable import TatamiCore

final class WorkspaceTests: XCTestCase {
    func testStageDeletionPreservesAnActiveDestination() throws {
        var state = WorkspaceState()
        let original = state.activeStageID
        let destination = state.removeStage(original)
        XCTAssertNotNil(destination)
        XCTAssertNotEqual(original, destination)
        XCTAssertTrue(state.stages.contains(where: { $0.id == destination }))
        _ = state.removeStage(state.stages.last!.id)
        XCTAssertNil(state.removeStage(state.activeStageID))
        try state.validate()
    }

    func testStageLimitsAndInvalidNames() {
        var state = WorkspaceState()
        XCTAssertNil(state.addStage(name: "  "))
        XCTAssertNil(state.addStage(name: String(repeating: "x", count: 61)))
        for index in 0..<6 { XCTAssertNotNil(state.addStage(name: "Stage \(index)")) }
        XCTAssertNil(state.addStage(name: "Too many"))
    }

    func testRoutingUsesFirstEnabledMatchAndHonorsExclusions() {
        var state = WorkspaceState()
        let work = state.stages[0].id, comms = state.stages[1].id
        state.rules = [RoutingRule(bundleID: "editor", appName: "Editor", titleContains: "invoice", stageID: comms),
                       RoutingRule(bundleID: "editor", appName: "Editor", stageID: work)]
        XCTAssertEqual(state.destination(bundleID: "editor", title: "INVOICE.txt"), comms)
        XCTAssertEqual(state.destination(bundleID: "editor", title: "readme.md"), work)
        state.rules[0].enabled = false
        XCTAssertEqual(state.destination(bundleID: "editor", title: "invoice.txt"), work)
        state.excludedBundleIDs = ["editor"]
        XCTAssertNil(state.destination(bundleID: "editor", title: "invoice.txt"))
    }

    func testDeletedRuleTargetDoesNotMatch() {
        var state = WorkspaceState()
        let target = state.stages[1].id
        state.rules = [RoutingRule(bundleID: "mail", appName: "Mail", stageID: target)]
        _ = state.removeStage(target)
        XCTAssertNil(state.destination(bundleID: "mail", title: "Inbox"))
    }

    func testAllSnapZonesRespectOffsetDisplayAndGap() {
        let display = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        XCTAssertEqual(SnapZone.allCases.count, 16)
        for zone in SnapZone.allCases {
            let frame = zone.frame(in: display, gap: 12)
            XCTAssertTrue(display.contains(frame), "\(zone)")
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)
        }
        XCTAssertEqual(SnapZone.center.frame(in: display), CGRect(x: -1440, y: 170, width: 960, height: 540))
        XCTAssertEqual(SnapZone.right.frame(in: display), CGRect(x: -960, y: -100, width: 960, height: 1080))
    }

    func testAccessibilityCoordinatesAcrossVerticalDisplays() {
        let above = CGRect(x: 0, y: 900, width: 1200, height: 800)
        XCTAssertEqual(Geometry.accessibilityFrame(above, primaryHeight: 900), CGRect(x: 0, y: -800, width: 1200, height: 800))
        let below = CGRect(x: 0, y: -800, width: 1200, height: 800)
        XCTAssertEqual(Geometry.accessibilityFrame(below, primaryHeight: 900), CGRect(x: 0, y: 900, width: 1200, height: 800))
    }

    func testGridDoesNotOverlapOrEscapeDisplay() {
        let display = CGRect(x: 0, y: 30, width: 1440, height: 850)
        for count in 1...50 {
            let frames = Geometry.grid(count: count, area: display, gap: 12)
            XCTAssertEqual(frames.count, count)
            for i in frames.indices {
                XCTAssertTrue(display.contains(frames[i]))
                for j in frames.indices where j > i { XCTAssertFalse(frames[i].intersects(frames[j])) }
            }
        }
        XCTAssertEqual(Geometry.grid(count: 0, area: display, gap: 12), [])
    }

    func testRescueFitsWindowToRemainingMonitor() {
        let area = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let original = CGRect(x: -2500, y: -500, width: 1920, height: 1080)
        XCTAssertEqual(Geometry.visibleFrame(original, in: area), area)
    }

    func testMalformedStateIsRejected() throws {
        var state = WorkspaceState()
        state.stages = []
        XCTAssertThrowsError(try state.validate())
        state = WorkspaceState(); state.activeStageID = UUID()
        XCTAssertThrowsError(try state.validate())
        state = WorkspaceState(); state.gap = .infinity
        XCTAssertThrowsError(try state.validate())
        state = WorkspaceState(); state.version = 99
        XCTAssertThrowsError(try state.validate())
        state = WorkspaceState(); state.stages.append(state.stages[0])
        XCTAssertThrowsError(try state.validate())
    }

    func testSavedWorkspaceRoundTrip() throws {
        var state = WorkspaceState()
        let window = WindowSnapshot(bundleID: "app", title: "Document", occurrence: 0, stageID: state.activeStageID, frame: CGRect(x: 10, y: 20, width: 500, height: 600))
        state.saved = [SavedWorkspace(name: "Desk", stages: state.stages, activeStageID: state.activeStageID, windows: [window])]
        let data = try JSONEncoder().encode(state)
        var restored = try JSONDecoder().decode(WorkspaceState.self, from: data)
        try restored.validate()
        XCTAssertEqual(restored.stages, state.stages)
        XCTAssertEqual(restored.saved[0].windows[0].frame, window.frame)
    }
}

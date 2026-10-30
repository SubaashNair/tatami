import XCTest
import CoreGraphics
@testable import TatamiCore

/// Regression tests for bugs found by the whole-app review.
final class ReviewFixTests: XCTestCase {
    // MARK: settings must keep saving after Stages are deleted or merged

    func testValidateDropsTiledEntriesForRemovedStages() throws {
        var state = WorkspaceState()
        let kept = state.stages[0].id.uuidString
        state.tiledDisplays = [kept: ["display-a"]]
        for _ in 0..<12 { state.tiledDisplays[UUID().uuidString] = ["display-a"] }  // Stages that were deleted or merged away
        try state.validate()
        XCTAssertEqual(Array(state.tiledDisplays.keys), [kept])
        XCTAssertEqual(state.tiledDisplays[kept], ["display-a"])
    }

    // MARK: renaming TabStack to Tiles must not lose saved settings

    func testSettingsSavedUnderTheOldTabStackKeyStillLoad() throws {
        var state = WorkspaceState()
        let stage = state.stages[0].id.uuidString
        state.tiledDisplays = [stage: ["display-a"]]
        let json = try JSONEncoder().encode(state)
        XCTAssertTrue(String(decoding: json, as: UTF8.self).contains("tiledDisplays"))
        // A settings file written before the rename used "tabStack".
        let legacy = String(decoding: json, as: UTF8.self).replacingOccurrences(of: "tiledDisplays", with: "tabStack")
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: Data(legacy.utf8))
        XCTAssertEqual(loaded.tiledDisplays[stage], ["display-a"])
    }

    // MARK: an app that did not answer a scan is not an app with no windows

    func testWindowsOfAppsThatFailedToAnswerAreKept() {
        let a = UUID(), b = UUID(), c = UUID()
        let known = [(id: a, pid: Int32(1)), (id: b, pid: Int32(2)), (id: c, pid: Int32(1))]
        // c was found again by the scan; a belongs to the same app but was not reported; b's app answered.
        XCTAssertEqual(ScanMerge.keptAfterFailure(known: known, merged: [c], failed: [1]), [a])
    }

    func testNothingIsKeptWhenEveryAppAnswered() {
        let a = UUID()
        XCTAssertEqual(ScanMerge.keptAfterFailure(known: [(id: a, pid: Int32(1))], merged: [], failed: []), [])
    }

    func testAWindowAlreadyMergedIsNotKeptTwice() {
        let a = UUID()
        XCTAssertEqual(ScanMerge.keptAfterFailure(known: [(id: a, pid: Int32(1))], merged: [a], failed: [1]), [])
    }

    // MARK: a zoomed pane must never be left empty

    func testRemovingTheLastTabOfTheZoomedPaneUnzooms() {
        let a = UUID(), b = UUID()
        var layout = PaneLayout(root: .pane(Pane(tabs: [a])))
        let second = layout.split(layout.focused, axis: .horizontal, moving: b)!
        layout.toggleZoom(second)
        layout.remove(b, keepEmptyPanes: true)
        XCTAssertNil(layout.zoomed)
    }

    func testZoomStaysWhileTheZoomedPaneStillHasTabs() {
        let a = UUID(), b = UUID(), c = UUID()
        var layout = PaneLayout(root: .pane(Pane(tabs: [a])))
        let second = layout.split(layout.focused, axis: .horizontal, moving: b)!
        layout.add(c, to: second)
        layout.toggleZoom(second)
        layout.remove(b, keepEmptyPanes: true)
        XCTAssertEqual(layout.zoomed, second)
    }
}

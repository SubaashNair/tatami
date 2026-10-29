import XCTest
@testable import TatamiCore

/// Tiles is the default mode, so new windows tile without a key press. A display can still be set to Freeform.
final class TilesDefaultTests: XCTestCase {
    private let stage = UUID()
    private let other = UUID()

    func testEveryDisplayStartsInTiles() {
        let state = WorkspaceState()
        XCTAssertTrue(state.tilesByDefault)
        XCTAssertTrue(state.isTiled(stage: stage, display: "display-a"))
        XCTAssertTrue(state.isTiled(stage: other, display: "display-b"))
    }

    func testOneDisplayCanBeSetToFreeformWithoutAffectingOthers() {
        var state = WorkspaceState()
        state.setTiled(false, stage: stage, display: "display-a")
        XCTAssertFalse(state.isTiled(stage: stage, display: "display-a"))
        XCTAssertTrue(state.isTiled(stage: stage, display: "display-b"))
        XCTAssertTrue(state.isTiled(stage: other, display: "display-a"))
    }

    func testSettingItBackToTilesClearsTheOverride() {
        var state = WorkspaceState()
        state.setTiled(false, stage: stage, display: "display-a")
        state.setTiled(true, stage: stage, display: "display-a")
        XCTAssertTrue(state.isTiled(stage: stage, display: "display-a"))
        XCTAssertTrue(state.freeformDisplays.isEmpty)
    }

    func testWithTilesOffByDefaultOnlyChosenDisplaysTile() {
        var state = WorkspaceState()
        state.tilesByDefault = false
        XCTAssertFalse(state.isTiled(stage: stage, display: "display-a"))
        state.setTiled(true, stage: stage, display: "display-a")
        XCTAssertTrue(state.isTiled(stage: stage, display: "display-a"))
        XCTAssertFalse(state.isTiled(stage: stage, display: "display-b"))
        state.setTiled(false, stage: stage, display: "display-a")
        XCTAssertFalse(state.isTiled(stage: stage, display: "display-a"))
        XCTAssertTrue(state.tiledDisplays.isEmpty)
    }

    func testAnExplicitTilesChoiceSurvivesTurningTheDefaultOff() {
        var state = WorkspaceState()
        state.setTiled(false, stage: stage, display: "display-a")
        state.setTiled(true, stage: stage, display: "display-a")  // the user chose Tiles for this display
        state.tilesByDefault = false
        XCTAssertTrue(state.isTiled(stage: stage, display: "display-a"))
        XCTAssertFalse(state.isTiled(stage: stage, display: "display-b"))
    }

    func testAnExplicitFreeformChoiceSurvivesTurningTheDefaultOn() {
        var state = WorkspaceState()
        state.tilesByDefault = false
        state.setTiled(false, stage: stage, display: "display-a")  // the user chose Freeform for this display
        state.tilesByDefault = true
        XCTAssertFalse(state.isTiled(stage: stage, display: "display-a"))
        XCTAssertTrue(state.isTiled(stage: stage, display: "display-b"))
    }

    func testValidateDropsFreeformOverridesForRemovedStages() throws {
        var state = WorkspaceState()
        let kept = state.stages[0].id
        state.setTiled(false, stage: kept, display: "display-a")
        for _ in 0..<12 { state.freeformDisplays[UUID().uuidString] = ["display-a"] }  // Stages that were deleted or merged away
        try state.validate()
        XCTAssertEqual(Array(state.freeformDisplays.keys), [kept.uuidString])
    }

    func testSettingsFromBeforeTheDefaultExistedLoadWithTilesOn() throws {
        var state = WorkspaceState()
        state.setTiled(false, stage: stage, display: "display-a")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object["tilesByDefault"] = nil
        object["freeformDisplays"] = nil
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(loaded.tilesByDefault)
        XCTAssertTrue(loaded.freeformDisplays.isEmpty)
    }

    func testPhotoBoothFloatsBecauseItCannotShrinkToAPane() {
        // Its minimum size made it spill over neighbouring panes; with tiling on by default that would be common.
        XCTAssertTrue(WorkspaceState().isFloating(bundleID: "com.apple.PhotoBooth", title: "Photo Booth"))
    }

    func testTheSettingsSurviveASaveAndLoad() throws {
        var state = WorkspaceState()
        state.tilesByDefault = false
        state.setTiled(true, stage: stage, display: "display-a")
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(state))
        XCTAssertFalse(loaded.tilesByDefault)
        XCTAssertTrue(loaded.isTiled(stage: stage, display: "display-a"))
    }
}

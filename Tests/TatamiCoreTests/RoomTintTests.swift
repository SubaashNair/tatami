import XCTest
@testable import TatamiCore

/// A Room can colour its tab bars so panes are told apart at a glance.
final class RoomTintTests: XCTestCase {
    func testARoomHasNoTintByDefaultAndOlderRoomsStillLoad() throws {
        XCTAssertNil(Stage(name: "Work").tint)
        let old = Data(#"{"id":"\#(UUID().uuidString)","name":"Work","symbol":"x"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(Stage.self, from: old).tint)
    }

    func testTheTintSurvivesASaveAndLoad() throws {
        var state = WorkspaceState()
        state.stages[1].tint = .teal
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(loaded.stages[1].tint, .teal)
        XCTAssertNil(loaded.stages[0].tint)
    }

    func testATintThisVersionDoesNotKnowIsDroppedNotFatal() throws {
        var state = WorkspaceState()
        state.stages[0].tint = .red
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        var stages = object["stages"] as! [[String: Any]]
        stages[0]["tint"] = "ultraviolet"
        object["stages"] = stages
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(loaded.stages[0].tint, "an unknown colour is ignored, the settings still load")
        XCTAssertEqual(loaded.stages.count, 3)
    }

    func testEveryTintHasAName() {
        XCTAssertEqual(RoomTint.allCases.count, 8)
        XCTAssertTrue(RoomTint.allCases.allSatisfy { !$0.label.isEmpty })
    }
}

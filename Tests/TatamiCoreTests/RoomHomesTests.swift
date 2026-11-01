import XCTest
@testable import TatamiCore

/// Room homes: a Room can live on a display, and open its windows there as tabs or panes.
final class RoomHomesTests: XCTestCase {
    private var state = WorkspaceState()
    private var work: UUID { state.stages[0].id }
    private var comms: UUID { state.stages[1].id }
    private var browse: UUID { state.stages[2].id }
    private let connected = ["A", "B", "C"]

    // MARK: placement

    func testARoomFollowsTheDeskWidePlacementUnlessItHasItsOwn() {
        state.newWindowPlacement = .own
        XCTAssertEqual(state.placement(forRoom: work), .own)
        state.setPlacement(.active, for: work)
        XCTAssertEqual(state.placement(forRoom: work), .active, "its own choice wins")
        XCTAssertEqual(state.placement(forRoom: comms), .own, "others still follow the desk-wide one")
        state.setPlacement(nil, for: work)
        XCTAssertEqual(state.placement(forRoom: work), .own)
    }

    func testAnUnknownRoomFallsBackToTheDeskWidePlacement() {
        state.newWindowPlacement = .adjacentRight
        XCTAssertEqual(state.placement(forRoom: UUID()), .adjacentRight)
    }

    // MARK: homes

    func testNoRoomHasAHomeByDefault() {
        XCTAssertNil(state.homeDisplay(of: work))
        XCTAssertNil(state.homeRoom(of: "A"))
    }

    func testSettingAHomeMakesThatDisplayShowTheRoomAndTurnsPerDisplayRoomsOn() {
        XCTAssertFalse(state.perDisplayRooms)
        XCTAssertTrue(state.setHome("A", for: comms, displays: connected))
        XCTAssertEqual(state.homeDisplay(of: comms), "A")
        XCTAssertTrue(state.perDisplayRooms, "homes need it, so it is turned on")
        XCTAssertEqual(state.activeRoomID(on: "A"), comms)
        XCTAssertEqual(state.activeRoomID(on: "B"), work, "other displays keep what they showed")
    }

    func testARoomWithAHomeOpensItsWindowsAsTabsUnlessYouChoseOtherwise() {
        state.newWindowPlacement = .automatic
        _ = state.setHome("A", for: comms, displays: connected)
        XCTAssertEqual(state.placement(forRoom: comms), .active, "tabs in the focused pane")
        XCTAssertNil(state.stages[1].placement, "a default, not a stored choice")
        state.setPlacement(.own, for: browse)
        _ = state.setHome("C", for: browse, displays: connected)
        XCTAssertEqual(state.placement(forRoom: browse), .own, "an explicit choice is kept")
        XCTAssertEqual(state.placement(forRoom: work), .automatic, "Rooms without a home are untouched")
    }

    func testAnUnknownRoomCannotBeGivenAHome() {
        XCTAssertFalse(state.setHome("A", for: UUID(), displays: connected))
        XCTAssertFalse(state.perDisplayRooms)
    }

    func testRemovingAHomeKeepsPerDisplayRoomsOnAndGoesBackToTheDeskWidePlacement() {
        state.newWindowPlacement = .automatic
        _ = state.setHome("A", for: comms, displays: connected)
        XCTAssertTrue(state.setHome(nil, for: comms, displays: connected))
        XCTAssertNil(state.homeDisplay(of: comms))
        XCTAssertTrue(state.perDisplayRooms)
        XCTAssertEqual(state.placement(forRoom: comms), .automatic, "tabs were only the default for a Room with a home")
    }

    func testMovingAHomeLeavesTheOldDisplayShowingTheRoomSoNothingIsHidden() {
        _ = state.setHome("A", for: comms, displays: connected)
        _ = state.setHome("B", for: comms, displays: connected)
        XCTAssertNil(state.homeRoom(of: "A"))
        XCTAssertEqual(state.activeRoomID(on: "A"), comms)
        XCTAssertEqual(state.activeRoomID(on: "B"), comms)
    }

    func testTwoRoomsMayShareADisplayAndTheFirstInTheListIsItsHomeRoom() {
        _ = state.setHome("B", for: browse, displays: connected)
        _ = state.setHome("B", for: comms, displays: connected)
        XCTAssertEqual(state.homeRoom(of: "B"), comms, "Comms comes before Browse")
    }

    func testAHomeOnlyCountsWhileItsDisplayIsConnectedAndTheModeIsOn() {
        _ = state.setHome("B", for: comms, displays: connected)
        XCTAssertEqual(state.effectiveHome(of: comms, connected: connected), "B")
        XCTAssertNil(state.effectiveHome(of: comms, connected: ["A", "C"]), "B is unplugged")
        state.perDisplayRooms = false
        XCTAssertNil(state.effectiveHome(of: comms, connected: connected), "homes are ignored with the mode off")
    }

    // MARK: routing to a home

    func testAnAppRuleSendsAWindowToItsRoomAndThatRoomsHomeDisplay() {
        _ = state.setHome("B", for: comms, displays: connected)
        state.rules = [RoutingRule(bundleID: "slack", appName: "Slack", stageID: comms)]
        let target = state.routedTarget(bundleID: "slack", title: "x", connected: connected)
        XCTAssertEqual(target, RoutedTarget(room: comms, display: "B"))
    }

    func testARoutedRoomWithNoHomeHasNoDisplay() {
        state.rules = [RoutingRule(bundleID: "slack", appName: "Slack", stageID: comms)]
        XCTAssertEqual(state.routedTarget(bundleID: "slack", title: "x", connected: connected), RoutedTarget(room: comms, display: nil))
    }

    func testAnUnpluggedHomeDisplayGivesNoDisplay() {
        _ = state.setHome("B", for: comms, displays: connected)
        state.rules = [RoutingRule(bundleID: "slack", appName: "Slack", stageID: comms)]
        XCTAssertEqual(state.routedTarget(bundleID: "slack", title: "x", connected: ["A"]), RoutedTarget(room: comms, display: nil))
    }

    func testNoRuleMeansNoTarget() {
        XCTAssertNil(state.routedTarget(bundleID: "unknown", title: "x", connected: connected))
    }

    func testAlwaysVisibleAppsAreNeverRouted() {
        state.excludedBundleIDs = ["slack"]
        state.rules = [RoutingRule(bundleID: "slack", appName: "Slack", stageID: comms)]
        XCTAssertNil(state.routedTarget(bundleID: "slack", title: "x", connected: connected))
    }

    // MARK: moving a window home

    func testAWindowOnTheWrongDisplayIsSentToItsRoomsHome() {
        _ = state.setHome("B", for: comms, displays: connected)
        XCTAssertEqual(state.homeToMoveTo(room: comms, currentDisplay: "A", connected: connected), "B")
    }

    func testAWindowAlreadyHomeOrWithoutAHomeStaysPut() {
        _ = state.setHome("B", for: comms, displays: connected)
        XCTAssertNil(state.homeToMoveTo(room: comms, currentDisplay: "B", connected: connected))
        XCTAssertNil(state.homeToMoveTo(room: work, currentDisplay: "A", connected: connected))
        XCTAssertNil(state.homeToMoveTo(room: comms, currentDisplay: "A", connected: ["A"]), "home unplugged")
    }

    // MARK: applying homes

    func testApplyingHomesPinsDisplaysThatHaveNoChoiceOfTheirOwnYet() {
        _ = state.setHome("A", for: work, displays: connected)
        _ = state.setHome("B", for: comms, displays: connected)
        _ = state.setHome("C", for: browse, displays: connected)
        state.activeStageID = work  // so a display with no pin would follow Work, not its home
        state.displayRooms = [:]
        state.applyHomes(connected: connected)
        XCTAssertEqual(state.activeRoomID(on: "A"), work)
        XCTAssertEqual(state.activeRoomID(on: "B"), comms)
        XCTAssertEqual(state.activeRoomID(on: "C"), browse)
    }

    func testApplyingHomesNeverOverridesWhatYouSwitchedADisplayTo() {
        _ = state.setHome("B", for: comms, displays: connected)
        state.displayRooms["B"] = browse  // you switched B yourself
        state.applyHomes(connected: connected)
        XCTAssertEqual(state.activeRoomID(on: "B"), browse)
    }

    func testApplyingHomesTreatsAPinToARemovedRoomAsNoChoice() {
        _ = state.setHome("B", for: comms, displays: connected)
        state.displayRooms["B"] = UUID()  // points at a Room that no longer exists
        state.applyHomes(connected: connected)
        XCTAssertEqual(state.displayRooms["B"], comms)
    }

    func testRemovingARoomClearsTheDisplayChoicesThatPointedAtIt() {
        state.perDisplayRooms = true
        state.switchRoom(browse, on: "B", displays: connected)
        let removed = browse
        _ = state.removeStage(removed)
        XCTAssertNil(state.displayRooms.values.first { $0 == removed })
    }

    func testMergingAllRoomsDropsTheHomeSoRoutedAppsStayWhereTheyOpen() {
        _ = state.setHome("B", for: work, displays: connected)
        _ = state.mergeAll()
        XCTAssertNil(state.homeDisplay(of: state.stages[0].id))
    }

    func testAWindowRoutedToAHomeThatIsShowingAnotherRoomWaitsThereUntilYouSwitch() {
        _ = state.setHome("B", for: comms, displays: connected)
        state.switchRoom(browse, on: "B", displays: connected)  // you switched B away from Comms
        XCTAssertEqual(state.homeToMoveTo(room: comms, currentDisplay: "A", connected: connected), "B", "it still goes home")
        XCTAssertFalse(state.isVisible(room: comms, bundleID: "x", on: "B"), "hidden until B shows Comms again")
        XCTAssertFalse(state.homeIsShowing(comms, connected: connected))
        state.switchRoom(comms, on: "B", displays: connected)
        XCTAssertTrue(state.homeIsShowing(comms, connected: connected))
        XCTAssertTrue(state.isVisible(room: comms, bundleID: "x", on: "B"))
    }

    func testAWholeOlderSettingsFileLoadsWithNoHomes() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WorkspaceState())) as! [String: Any]
        var stages = object["stages"] as! [[String: Any]]
        for index in stages.indices { stages[index].removeValue(forKey: "homeDisplay"); stages[index].removeValue(forKey: "placement") }
        object["stages"] = stages
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(loaded.stages.allSatisfy { $0.homeDisplay == nil && $0.placement == nil })
    }

    // MARK: saved settings

    func testHomesAndPlacementSurviveASaveAndLoad() throws {
        _ = state.setHome("B", for: comms, displays: connected)
        state.setPlacement(.active, for: comms)
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(loaded.homeDisplay(of: loaded.stages[1].id), "B")
        XCTAssertEqual(loaded.placement(forRoom: loaded.stages[1].id), .active)
    }

    func testOlderRoomsWithoutThoseKeysStillLoad() throws {
        let old = Data(#"{"id":"\#(UUID().uuidString)","name":"Work","symbol":"x"}"#.utf8)
        let stage = try JSONDecoder().decode(Stage.self, from: old)
        XCTAssertNil(stage.homeDisplay)
        XCTAssertNil(stage.placement)
    }

    func testAnAbsurdlyLongHomeKeyIsDroppedOnValidation() throws {
        _ = state.setHome("A", for: work, displays: [])
        state.stages[0].homeDisplay = String(repeating: "x", count: 500)
        try state.validate()
        XCTAssertNil(state.stages[0].homeDisplay)
    }
}

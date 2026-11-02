import XCTest
@testable import TatamiCore

/// Per-display Rooms: each display can show its own Room. Off by default, where one Room is active everywhere.
final class RoomsPerDisplayTests: XCTestCase {
    private var state = WorkspaceState()
    private var work: UUID { state.stages[0].id }
    private var comms: UUID { state.stages[1].id }
    private var browse: UUID { state.stages[2].id }

    /// Two connected displays, A and B.
    private func switchTo(_ id: UUID, on display: String) { state.switchRoom(id, on: display, displays: ["A", "B"]) }

    // MARK: off (the default)

    func testItIsOffByDefaultAndEveryDisplayFollowsTheActiveRoom() {
        XCTAssertFalse(state.perDisplayRooms)
        XCTAssertEqual(state.activeRoomID(on: "A"), work)
        XCTAssertEqual(state.activeRoomID(on: "B"), work)
        XCTAssertEqual(state.activeRoomID(on: nil), work)
    }

    func testSwitchingWhileOffChangesEveryDisplay() {
        XCTAssertTrue(state.switchRoom(comms, on: "A", displays: ["A", "B"]))
        XCTAssertEqual(state.activeRoomID(on: "A"), comms)
        XCTAssertEqual(state.activeRoomID(on: "B"), comms)
        XCTAssertEqual(state.activeStageID, comms)
        XCTAssertTrue(state.displayRooms.isEmpty)
    }

    func testAWindowIsVisibleWhenItsRoomIsActiveNoMatterWhichDisplayItIsOn() {
        XCTAssertTrue(state.isVisible(room: work, bundleID: "x", on: "A"))
        XCTAssertTrue(state.isVisible(room: work, bundleID: "x", on: "B"))
        XCTAssertFalse(state.isVisible(room: comms, bundleID: "x", on: "B"))
    }

    // MARK: on

    func testEachDisplayKeepsItsOwnRoom() {
        state.perDisplayRooms = true
        state.switchRoom(comms, on: "B", displays: ["A", "B"])
        XCTAssertEqual(state.activeRoomID(on: "A"), work, "A was not switched")
        XCTAssertEqual(state.activeRoomID(on: "B"), comms)
        state.switchRoom(browse, on: "A", displays: ["A", "B"])
        XCTAssertEqual(state.activeRoomID(on: "A"), browse)
        XCTAssertEqual(state.activeRoomID(on: "B"), comms, "B keeps its own Room")
    }

    func testSwitchingOneDisplayNeverMovesAnother() {
        state.perDisplayRooms = true
        switchTo(comms, on: "B")
        XCTAssertEqual(state.activeRoomID(on: "A"), work, "A was on Work before and still is")
        switchTo(browse, on: "A")
        XCTAssertEqual(state.activeRoomID(on: "B"), comms)
    }

    func testTheLastSwitchedRoomStaysTheOneEverythingElseUses() {
        state.perDisplayRooms = true
        switchTo(comms, on: "B")
        XCTAssertEqual(state.activeStageID, comms)
        XCTAssertEqual(state.activeRoomID(on: "C"), comms, "an unseen display follows the last switch")
        XCTAssertEqual(state.activeRoomID(on: nil), comms)
    }

    func testVisibilityDependsOnTheDisplayTheWindowIsOn() {
        state.perDisplayRooms = true
        switchTo(work, on: "A")
        switchTo(comms, on: "B")
        XCTAssertTrue(state.isVisible(room: work, bundleID: "x", on: "A"))
        XCTAssertFalse(state.isVisible(room: work, bundleID: "x", on: "B"), "a Work window on the Comms display is hidden")
        XCTAssertTrue(state.isVisible(room: comms, bundleID: "x", on: "B"))
        XCTAssertFalse(state.isVisible(room: comms, bundleID: "x", on: "A"))
    }

    func testAlwaysVisibleAppsShowOnEveryDisplayInEveryRoom() {
        state.perDisplayRooms = true
        state.excludedBundleIDs = ["music"]
        switchTo(comms, on: "B")
        XCTAssertTrue(state.isVisible(room: browse, bundleID: "music", on: "A"))
        XCTAssertTrue(state.isVisible(room: browse, bundleID: "music", on: "B"))
    }

    func testAWindowSentToADisplayJoinsThatDisplaysRoom() {
        state.perDisplayRooms = true
        switchTo(comms, on: "B")
        XCTAssertEqual(state.roomForWindowSent(to: "B"), comms)
        XCTAssertEqual(state.roomForWindowSent(to: "A"), work)
    }

    func testSwitchingEverywhereMovesAllDisplaysTogether() {
        state.perDisplayRooms = true
        switchTo(comms, on: "B")
        switchTo(browse, on: "A")
        state.switchRoomEverywhere(work)
        XCTAssertEqual(state.activeRoomID(on: "A"), work)
        XCTAssertEqual(state.activeRoomID(on: "B"), work)
        XCTAssertTrue(state.displayRooms.isEmpty)
    }

    func testNextAndPreviousStepFromTheDisplaysOwnRoom() {
        state.perDisplayRooms = true
        switchTo(comms, on: "B")
        XCTAssertEqual(state.stageID(offset: 1, on: "B"), browse)
        XCTAssertEqual(state.stageID(offset: -1, on: "B"), work)
        XCTAssertEqual(state.stageID(offset: 1, on: "A"), comms, "A is on Work")
    }

    func testTurningItOffCollapsesEveryDisplayOntoTheLastSwitchedRoom() {
        state.perDisplayRooms = true
        switchTo(browse, on: "A")
        switchTo(comms, on: "B")
        state.setPerDisplayRooms(false)
        XCTAssertFalse(state.perDisplayRooms)
        XCTAssertEqual(state.activeRoomID(on: "A"), comms)
        XCTAssertEqual(state.activeRoomID(on: "B"), comms)
        XCTAssertTrue(state.displayRooms.isEmpty)
    }

    func testTurningItOnStartsEveryDisplayOnTheCurrentRoom() {
        state.perDisplayRooms = true
        switchTo(browse, on: "A")
        switchTo(comms, on: "B")
        state.setPerDisplayRooms(false)
        state.setPerDisplayRooms(true)
        XCTAssertTrue(state.displayRooms.isEmpty)
        XCTAssertEqual(state.activeRoomID(on: "A"), comms)
        XCTAssertEqual(state.activeRoomID(on: "B"), comms)
    }

    func testTurningItOnAgainKeepsWhatEachDisplayShows() {
        state.perDisplayRooms = true
        switchTo(browse, on: "A")
        switchTo(comms, on: "B")
        state.setPerDisplayRooms(true)
        XCTAssertEqual(state.activeRoomID(on: "A"), browse)
        XCTAssertEqual(state.activeRoomID(on: "B"), comms)
    }

    func testWithoutADisplayTheSwitchIsRefusedInsteadOfMovingEveryDisplay() {
        state.perDisplayRooms = true
        switchTo(browse, on: "A")
        switchTo(comms, on: "B")
        XCTAssertFalse(state.switchRoom(work, on: nil, displays: ["A", "B"]))
        XCTAssertEqual(state.activeRoomID(on: "A"), browse)
        XCTAssertEqual(state.activeRoomID(on: "B"), comms)
    }

    // MARK: safety

    func testSwitchingToAnUnknownRoomChangesNothing() {
        state.perDisplayRooms = true
        XCTAssertFalse(state.switchRoom(UUID(), on: "A", displays: ["A", "B"]))
        XCTAssertEqual(state.activeRoomID(on: "A"), work)
        XCTAssertTrue(state.displayRooms.isEmpty)
    }

    func testADeletedRoomFallsBackToTheLastSwitchedRoom() {
        state.perDisplayRooms = true
        switchTo(comms, on: "B")
        switchTo(browse, on: "A")  // the last switch: Browse is now the fallback, and is not the first Room
        let removed = comms, fallback = browse
        state.stages.removeAll { $0.id == removed }
        XCTAssertEqual(state.activeRoomID(on: "B"), fallback, "never an id that no longer exists")
    }

    func testValidationDropsEntriesForRoomsThatNoLongerExist() throws {
        state.perDisplayRooms = true
        switchTo(comms, on: "B")
        switchTo(work, on: "A")
        let removed = comms
        state.stages.removeAll { $0.id == removed }
        try state.validate()
        XCTAssertNil(state.displayRooms["B"])
        XCTAssertEqual(state.displayRooms["A"], work)
    }

    func testMergingAllRoomsLeavesNoDisplayPointingAtARemovedRoom() {
        state.perDisplayRooms = true
        switchTo(browse, on: "B")
        let kept = state.mergeAll()
        XCTAssertEqual(state.activeRoomID(on: "B"), kept)
        XCTAssertTrue(state.displayRooms.isEmpty)
    }

    func testManyRememberedDisplaysAreTrimmedInsteadOfBreakingSaving() throws {
        state.perDisplayRooms = true
        for index in 0..<33 { state.displayRooms["D\(index)"] = work }
        XCTAssertNoThrow(try state.validate(), "saving must never fail because of old display entries")
        XCTAssertEqual(state.displayRooms.count, 32)
    }

    func testExactlyTheLimitIsKeptAsIs() throws {
        state.perDisplayRooms = true
        for index in 0..<32 { state.displayRooms["D\(index)"] = work }
        try state.validate()
        XCTAssertEqual(state.displayRooms.count, 32)
    }

    // MARK: saved settings

    func testTheSettingsSurviveASaveAndLoad() throws {
        state.perDisplayRooms = true
        switchTo(comms, on: "B")
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(loaded.perDisplayRooms)
        XCTAssertEqual(loaded.activeRoomID(on: "B"), comms)
    }

    func testOlderFilesWithoutTheKeysLoadWithItOff() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WorkspaceState())) as! [String: Any]
        object.removeValue(forKey: "perDisplayRooms")
        object.removeValue(forKey: "displayRooms")
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(loaded.perDisplayRooms)
        XCTAssertTrue(loaded.displayRooms.isEmpty)
    }

    // MARK: active check and display tracking (phase 2)

    func testIsActiveRoomMatchesTheRoomShowingOnThatDisplay() {
        XCTAssertTrue(state.isActiveRoom(work, on: "A"))
        XCTAssertFalse(state.isActiveRoom(comms, on: "A"))
        state.perDisplayRooms = true
        switchTo(comms, on: "B")
        XCTAssertTrue(state.isActiveRoom(work, on: "A"))
        XCTAssertTrue(state.isActiveRoom(comms, on: "B"))
        XCTAssertFalse(state.isActiveRoom(work, on: "B"))
    }

    func testTheTrackerReportsAMoveToAnotherDisplayOnce() {
        var tracker = WindowDisplayTracker()
        let window = UUID()
        XCTAssertNil(tracker.update(window: window, display: "A"), "first sighting is not a move")
        XCTAssertNil(tracker.update(window: window, display: "A"))
        XCTAssertEqual(tracker.update(window: window, display: "B"), "A")
        XCTAssertNil(tracker.update(window: window, display: "B"), "already reported")
    }

    func testTheTrackerIgnoresAWindowWithNoDisplay() {
        var tracker = WindowDisplayTracker()
        let window = UUID()
        _ = tracker.update(window: window, display: "A")
        XCTAssertNil(tracker.update(window: window, display: nil))
        XCTAssertEqual(tracker.update(window: window, display: "B"), "A", "the old display is still remembered")
    }

    func testTheTrackerForgetsWindowsThatAreGone() {
        var tracker = WindowDisplayTracker()
        let kept = UUID(), gone = UUID()
        _ = tracker.update(window: kept, display: "A")
        _ = tracker.update(window: gone, display: "A")
        tracker.keepOnly([kept])
        XCTAssertNil(tracker.update(window: gone, display: "B"), "forgotten, so this is a first sighting")
        XCTAssertEqual(tracker.update(window: kept, display: "B"), "A")
    }
}

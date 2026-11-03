import XCTest
@testable import TatamiCore

/// Send a Room to another display: the two displays swap Rooms, and what belongs to a Room (its Tiles mode, its home) goes with it.
final class RoomSwapTests: XCTestCase {
    private var state = WorkspaceState()
    private var work: UUID { state.stages[0].id }
    private var comms: UUID { state.stages[1].id }
    private var browse: UUID { state.stages[2].id }
    private let connected = ["A", "B", "C"]

    /// Display A shows Work, B shows Comms, C shows Browse.
    private func threeDisplays() {
        state.perDisplayRooms = true
        state.switchRoom(work, on: "A", displays: connected)
        state.switchRoom(comms, on: "B", displays: connected)
        state.switchRoom(browse, on: "C", displays: connected)
    }

    func testTwoDisplaysSwapRoomsAndTheThirdIsUntouched() {
        threeDisplays()
        let swap = state.swapRooms(between: "A", and: "B", displays: connected)
        XCTAssertEqual(swap, RoomSwap(first: work, second: comms, firstDisplay: "A", secondDisplay: "B"))
        XCTAssertEqual(state.activeRoomID(on: "A"), comms)
        XCTAssertEqual(state.activeRoomID(on: "B"), work)
        XCTAssertEqual(state.activeRoomID(on: "C"), browse)
    }

    func testADisplayThatHadNoChoiceOfItsOwnDoesNotChangeRoom() {
        state.perDisplayRooms = true
        state.switchRoom(work, on: "A", displays: ["A", "B"])
        state.switchRoom(comms, on: "B", displays: ["A", "B"])
        // D was plugged in later and has no entry, so it follows the last switched Room (Comms)
        XCTAssertEqual(state.activeRoomID(on: "D"), comms)
        _ = state.swapRooms(between: "A", and: "B", displays: ["A", "B", "D"])
        XCTAssertEqual(state.activeRoomID(on: "D"), comms, "D keeps showing what it showed")
    }

    func testTheRoomYouSentIsTheLastSwitchedOne() {
        threeDisplays()
        _ = state.swapRooms(between: "A", and: "B", displays: connected)
        XCTAssertEqual(state.activeStageID, work)
    }

    func testItNeedsPerDisplayRoomsAndTwoDifferentDisplaysShowingDifferentRooms() {
        threeDisplays()
        XCTAssertNil(state.swapRooms(between: "A", and: "A", displays: connected))
        state.switchRoom(work, on: "B", displays: connected)  // A and B both show Work
        XCTAssertNil(state.swapRooms(between: "A", and: "B", displays: connected), "nothing to swap")
        state.perDisplayRooms = false
        XCTAssertNil(state.swapRooms(between: "A", and: "C", displays: connected), "one Room for the whole desk has nothing to send")
    }

    func testTilesModeGoesWithTheRoom() {
        threeDisplays()
        state.setTiled(true, stage: work, display: "A")
        state.setTiled(false, stage: comms, display: "B")
        _ = state.swapRooms(between: "A", and: "B", displays: connected)
        XCTAssertTrue(state.isTiled(stage: work, display: "B"), "Work was tiled on A, so it is tiled on B")
        XCTAssertFalse(state.isTiled(stage: comms, display: "A"), "Comms was freeform on B, so it is freeform on A")
    }

    func testARoomThatLivedOnADisplayNowLivesOnTheOther() {
        threeDisplays()
        _ = state.setHome("A", for: work, displays: connected)
        _ = state.setHome("B", for: comms, displays: connected)
        _ = state.setHome("C", for: browse, displays: connected)
        state.switchRoom(work, on: "A", displays: connected)
        _ = state.swapRooms(between: "A", and: "B", displays: connected)
        XCTAssertEqual(state.homeDisplay(of: work), "B")
        XCTAssertEqual(state.homeDisplay(of: comms), "A")
        XCTAssertEqual(state.homeDisplay(of: browse), "C", "unrelated Rooms keep their home")
    }

    func testARoomWhoseHomeIsElsewhereKeepsIt() {
        threeDisplays()
        _ = state.setHome("C", for: work, displays: connected)
        state.switchRoom(work, on: "A", displays: connected)
        _ = state.swapRooms(between: "A", and: "B", displays: connected)
        XCTAssertEqual(state.homeDisplay(of: work), "C", "its home was not the display it was sent from")
    }

    func testSwappingTwiceGivesTheOriginalArrangementBack() {
        threeDisplays()
        _ = state.swapRooms(between: "A", and: "B", displays: connected)
        _ = state.swapRooms(between: "A", and: "B", displays: connected)
        XCTAssertEqual(state.activeRoomID(on: "A"), work)
        XCTAssertEqual(state.activeRoomID(on: "B"), comms)
    }

    func testADisplayWithNoChoiceOfItsOwnCountsAsShowingTheLastSwitchedRoom() {
        state.perDisplayRooms = true
        state.switchRoom(comms, on: "B", displays: ["A", "B"])  // A keeps Work, pinned by that switch
        let swap = state.swapRooms(between: "B", and: "D", displays: ["A", "B", "D"])      // D is new: it follows the last switched Room (Comms)
        XCTAssertNil(swap, "B and D both show Comms, so there is nothing to swap")
    }
}

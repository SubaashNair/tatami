import XCTest
@testable import TatamiCore

/// "Previous Room" (AeroSpace's workspace-back-and-forth), kept per display so each screen flips between its own last two Rooms.
final class RoomHistoryTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()
    private var history = RoomHistory()
    private var all: [UUID] { [a, b, c] }

    func testThereIsNothingToGoBackToAtFirst() {
        XCTAssertNil(history.back(on: "X", current: a, rooms: all))
    }

    func testBackReturnsTheRoomYouJustLeft() {
        history.record(from: a, to: b, on: "X")
        XCTAssertEqual(history.back(on: "X", current: b, rooms: all), a)
    }

    func testBackAndBackAgainFlipsBetweenTheTwoRooms() {
        history.record(from: a, to: b, on: "X")
        let first = history.back(on: "X", current: b, rooms: all)!
        history.record(from: b, to: first, on: "X")  // the switch back is recorded like any other
        XCTAssertEqual(history.back(on: "X", current: first, rooms: all), b)
    }

    func testEachDisplayHasItsOwnHistory() {
        history.record(from: a, to: b, on: "X")
        history.record(from: c, to: a, on: "Y")
        XCTAssertEqual(history.back(on: "X", current: b, rooms: all), a)
        XCTAssertEqual(history.back(on: "Y", current: a, rooms: all), c)
        XCTAssertNil(history.back(on: "Z", current: a, rooms: all))
    }

    func testWithoutPerDisplayRoomsThereIsOneHistoryForTheWholeDesk() {
        history.record(from: a, to: b, on: nil)
        XCTAssertEqual(history.back(on: nil, current: b, rooms: all), a)
        XCTAssertNil(history.back(on: "X", current: b, rooms: all), "a display's own history is separate")
    }

    func testSwitchingToTheRoomAlreadyShownRecordsNothing() {
        history.record(from: a, to: b, on: "X")
        history.record(from: b, to: b, on: "X")
        XCTAssertEqual(history.back(on: "X", current: b, rooms: all), a, "still the Room before")
    }

    func testARoomThatNoLongerExistsIsNotOfferedAndNeitherIsTheCurrentOne() {
        history.record(from: a, to: b, on: "X")
        XCTAssertNil(history.back(on: "X", current: b, rooms: [b, c]), "Room A was removed")
        XCTAssertNil(history.back(on: "X", current: a, rooms: all), "never the Room already showing")
    }

    func testForgettingARoomRemovesItEverywhere() {
        history.record(from: a, to: b, on: "X")
        history.record(from: a, to: c, on: "Y")
        history.forget(a)
        XCTAssertNil(history.back(on: "X", current: b, rooms: all))
        XCTAssertNil(history.back(on: "Y", current: c, rooms: all))
    }

    func testTheLatestSwitchWins() {
        history.record(from: a, to: b, on: "X")
        history.record(from: b, to: c, on: "X")
        XCTAssertEqual(history.back(on: "X", current: c, rooms: all), b)
    }
}

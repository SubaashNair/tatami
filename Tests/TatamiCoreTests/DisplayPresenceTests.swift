import XCTest
@testable import TatamiCore

/// A display that vanishes for a moment (waking from sleep, a flaky cable) must not be treated as unplugged.
final class DisplayPresenceTests: XCTestCase {
    private var presence = DisplayPresence(grace: 8)

    func testTheFirstLookReportsEveryDisplayAsNewAndNothingGone() {
        let change = presence.update(current: ["A", "B"], now: 0)
        XCTAssertEqual(change.returned, ["A", "B"])
        XCTAssertTrue(change.gone.isEmpty)
    }

    func testADisplayThatIsMissingForAWhileIsNotGoneYet() {
        _ = presence.update(current: ["A", "B"], now: 0)
        let first = presence.update(current: ["A"], now: 1)
        XCTAssertTrue(first.gone.isEmpty, "it may be back in a moment")
        XCTAssertEqual(presence.pendingMissing, ["B"])
        XCTAssertTrue(presence.update(current: ["A"], now: 7.9).gone.isEmpty)
    }

    func testItIsGoneOnlyOnceItHasBeenMissingForTheWholeGracePeriod() {
        _ = presence.update(current: ["A", "B"], now: 0)
        _ = presence.update(current: ["A"], now: 1)
        let confirmed = presence.update(current: ["A"], now: 9)
        XCTAssertEqual(confirmed.gone, ["B"])
        XCTAssertTrue(presence.pendingMissing.isEmpty)
        XCTAssertTrue(presence.update(current: ["A"], now: 20).gone.isEmpty, "reported once")
    }

    func testADisplayBackBeforeTheGraceEndsWasNeverGoneAndNeverReturned() {
        _ = presence.update(current: ["A", "B"], now: 0)
        _ = presence.update(current: ["A"], now: 2)
        let back = presence.update(current: ["A", "B"], now: 5)
        XCTAssertTrue(back.gone.isEmpty)
        XCTAssertTrue(back.returned.isEmpty, "nothing was moved, so there is nothing to restore")
        XCTAssertTrue(presence.pendingMissing.isEmpty)
        // and the clock starts again if it vanishes later
        _ = presence.update(current: ["A"], now: 6)
        XCTAssertTrue(presence.update(current: ["A"], now: 12).gone.isEmpty)
        XCTAssertEqual(presence.update(current: ["A"], now: 14.5).gone, ["B"])
    }

    func testAConfirmedGoneDisplayThatComesBackIsReportedAsReturned() {
        _ = presence.update(current: ["A", "B"], now: 0)
        _ = presence.update(current: ["A"], now: 1)
        _ = presence.update(current: ["A"], now: 10)
        let back = presence.update(current: ["A", "B"], now: 30)
        XCTAssertEqual(back.returned, ["B"])
    }

    func testABrandNewDisplayIsReportedAtOnce() {
        _ = presence.update(current: ["A"], now: 0)
        XCTAssertEqual(presence.update(current: ["A", "C"], now: 1).returned, ["C"])
    }

    func testSeveralMissingDisplaysEachHaveTheirOwnClock() {
        _ = presence.update(current: ["A", "B", "C"], now: 0)
        _ = presence.update(current: ["A", "C"], now: 1)   // B missing from 1
        _ = presence.update(current: ["A"], now: 5)        // C missing from 5
        let change = presence.update(current: ["A"], now: 9.5)
        XCTAssertEqual(change.gone, ["B"], "C has only been missing for 4.5 s")
        XCTAssertEqual(presence.pendingMissing, ["C"])
    }

    func testItSaysWhenToLookAgain() {
        XCTAssertNil(presence.nextCheck(now: 0), "nothing is pending")
        _ = presence.update(current: ["A", "B"], now: 0)
        _ = presence.update(current: ["A"], now: 2)
        XCTAssertEqual(presence.nextCheck(now: 3) ?? -1, 7, accuracy: 0.001, "missing since 2, confirmed at 10")
        XCTAssertEqual(presence.nextCheck(now: 11) ?? -1, 0, accuracy: 0.001, "already due")
    }

    func testTheGraceBoundaryIsInclusive() {
        _ = presence.update(current: ["A", "B"], now: 0)
        _ = presence.update(current: ["A"], now: 10)
        XCTAssertTrue(presence.update(current: ["A"], now: 17.999).gone.isEmpty)
        XCTAssertEqual(presence.update(current: ["A"], now: 18).gone, ["B"], "missing for exactly the grace period")
    }

    func testNothingIsPendingOnceEveryMissingDisplayIsConfirmed() {
        _ = presence.update(current: ["A", "B"], now: 0)
        _ = presence.update(current: ["A"], now: 1)
        _ = presence.update(current: ["A"], now: 9)
        XCTAssertNil(presence.nextCheck(now: 9))
    }

    func testAnEmptyListHeldPastTheGraceDoesConfirmEveryDisplayGone() {
        _ = presence.update(current: ["A", "B"], now: 0)
        _ = presence.update(current: [], now: 1)
        XCTAssertEqual(presence.update(current: [], now: 9).gone, ["A", "B"])
    }

    func testAnEmptyDisplayListNeverConfirmsEverythingGoneInstantly() {
        _ = presence.update(current: ["A", "B"], now: 0)
        let change = presence.update(current: [], now: 1)
        XCTAssertTrue(change.gone.isEmpty, "a list with no displays is almost always a glitch")
        XCTAssertEqual(presence.pendingMissing, ["A", "B"])
    }
}

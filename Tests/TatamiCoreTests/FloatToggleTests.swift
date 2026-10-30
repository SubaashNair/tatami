import XCTest
@testable import TatamiCore

/// One key flips an app between floating and tiled; pressing it again undoes it and leaves no stray rule behind.
final class FloatToggleTests: XCTestCase {
    private let app = "com.example.Notes"
    private let floater = "com.apple.PhotoBooth"  // floats by default

    func testATiledAppFloatsThenTilesAgainWithoutLeavingARule() {
        var state = WorkspaceState()
        XCTAssertFalse(state.isFloating(bundleID: app, title: "Todo"))
        XCTAssertTrue(state.toggleAppBehavior(bundleID: app))
        XCTAssertTrue(state.isFloating(bundleID: app, title: "Todo"))
        XCTAssertFalse(state.toggleAppBehavior(bundleID: app))
        XCTAssertFalse(state.isFloating(bundleID: app, title: "Todo"))
        XCTAssertTrue(state.behaviorRules.isEmpty)
    }

    func testAnAppThatFloatsByDefaultCanBeTiledAndBack() {
        var state = WorkspaceState()
        XCTAssertTrue(state.isFloating(bundleID: floater, title: "Photo Booth"))
        XCTAssertFalse(state.toggleAppBehavior(bundleID: floater))
        XCTAssertFalse(state.isFloating(bundleID: floater, title: "Photo Booth"))  // a saved rule overrides the default list
        XCTAssertEqual(state.behaviorRules.count, 1)
        XCTAssertTrue(state.toggleAppBehavior(bundleID: floater))
        XCTAssertTrue(state.isFloating(bundleID: floater, title: "Photo Booth"))
        XCTAssertTrue(state.behaviorRules.isEmpty)
    }

    func testOtherAppsAreUnaffected() {
        var state = WorkspaceState()
        _ = state.toggleAppBehavior(bundleID: app)
        XCTAssertFalse(state.isFloating(bundleID: "com.example.Mail", title: "Inbox"))
    }

    func testARuleForASpecificTitleSurvives() {
        var state = WorkspaceState()
        state.behaviorRules = [WindowBehaviorRule(bundleID: app, titleContains: "Meeting", behavior: .floating)]
        _ = state.toggleAppBehavior(bundleID: app)
        _ = state.toggleAppBehavior(bundleID: app)
        XCTAssertEqual(state.behaviorRules.map(\.titleContains), ["Meeting"])
        XCTAssertTrue(state.isFloating(bundleID: app, title: "Weekly Meeting"))
    }

    func testAnAppRuleDoesNotHideAMoreSpecificTitleRule() {
        var state = WorkspaceState()
        state.behaviorRules = [WindowBehaviorRule(bundleID: app, titleContains: "Calls", behavior: .managed)]
        XCTAssertTrue(state.toggleAppBehavior(bundleID: app))  // the app floats now...
        XCTAssertTrue(state.isFloating(bundleID: app, title: "Notes"))
        XCTAssertFalse(state.isFloating(bundleID: app, title: "Calls"))  // ...except windows its title rule keeps tiled
    }

    func testRepeatedPressesAlwaysFlipTheWholeApp() {
        var state = WorkspaceState()
        var expected = false
        for _ in 0..<5 {
            expected.toggle()
            XCTAssertEqual(state.toggleAppBehavior(bundleID: app), expected)
            XCTAssertEqual(state.isFloating(bundleID: app, title: "Anything"), expected)
        }
        XCTAssertLessThanOrEqual(state.behaviorRules.count, 1)
    }
}

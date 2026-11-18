import XCTest
import CoreGraphics
@testable import TatamiCore

/// Regressions found in a code audit: config parsing, AI plan validation, AeroSpace import and corrupt saved layouts.
final class AuditFixesTests: XCTestCase {
    // MARK: monitor lists

    func testMultiLineMonitorListKeepsKeywords() {
        let text = """
        [workspace-to-monitor-force-assignment]
        1 = [
          'main',
          'built-in'
        ]
        """
        XCTAssertEqual(AeroSpaceConfig.parseMonitorAssignments(text)["1"], [.main, .builtIn])
    }

    func testSpaceAfterQuotedNameIsNotPartOfIt() {
        let text = """
        [workspace-to-monitor-force-assignment]
        2 = ['G27q' , 'secondary' ]
        """
        XCTAssertEqual(AeroSpaceConfig.parseMonitorAssignments(text)["2"], [.pattern("G27q"), .secondary])
    }

    // MARK: AI plan

    private let context = PlanContext(
        windows: [PlanWindow(ref: "w1", appName: "Xcode", bundleID: "com.apple.dt.Xcode", title: "T", stageName: "Work", display: 1, frame: .zero)],
        stageNames: ["Work"],
        displays: [CGSize(width: 1512, height: 944), CGSize(width: 2560, height: 1440)])

    func testSnapWithUnreadableDisplayIsDroppedNotMovedToTheCurrentDisplay() throws {
        for display in [#""external""#, "1.5", "true"] {
            let plan = try AIPlan.parse(#"{"summary":"s","actions":[{"type":"snap","window":"w1","zone":"left","display":\#(display)}]}"#)
            let result = plan.validate(against: context)
            XCTAssertTrue(result.valid.isEmpty, "display \(display) must not snap on the current display")
            XCTAssertEqual(result.dropped.count, 1)
        }
    }

    func testSnapWithNullOrMissingDisplayStillWorks() throws {
        for extra in ["", #","display":null"#, #","display":"2""#] {
            let plan = try AIPlan.parse(#"{"summary":"s","actions":[{"type":"snap","window":"w1","zone":"left"\#(extra)}]}"#)
            XCTAssertEqual(plan.validate(against: context).valid.count, 1, "extra: \(extra)")
        }
    }

    // MARK: AeroSpace import

    func testRuleWithAppIDAndNameRegexNeedsBoth() {
        let installed = [InstalledApp(bundleID: "com.google.Chrome", name: "Google Chrome")]
        let miss = [AeroRule(appID: "com.google.Chrome", nameRegex: "Safari", workspace: "W", floating: false, unsupported: [])]
        XCTAssertTrue(AeroImport.plan(miss, installed: installed).entries.isEmpty)
        let hit = [AeroRule(appID: "com.google.Chrome", nameRegex: "chrome", workspace: "W", floating: false, unsupported: [])]
        XCTAssertEqual(AeroImport.plan(hit, installed: installed).entries.first?.apps, installed)
    }

    // MARK: corrupt saved layouts

    func testEmptySplitDoesNotCrashPruning() {
        var layout = PaneLayout(root: .pane(Pane()))
        layout.root = .split(.horizontal, [])
        let pruned = layout.pruned()
        XCTAssertEqual(pruned.root.panes.count, 1)
        XCTAssertEqual(pruned.focused, pruned.root.paneIDs[0])
    }

    func testZeroOrNaNWeightsStillGiveFiniteFrames() {
        for weight in [0, Double.nan, -1] {
            let a = Pane(), b = Pane()
            let root = LayoutNode.split(.horizontal, [Child(node: .pane(a), weight: weight), Child(node: .pane(b), weight: weight)])
            let frames = PaneLayout(root: root).frames(in: CGRect(x: 0, y: 0, width: 1000, height: 500), gap: 0, tabBar: 0)
            XCTAssertEqual(frames.count, 2)
            for frame in frames.values {
                XCTAssertTrue(frame.pane.width.isFinite && frame.pane.width > 0, "weight \(weight) gave \(frame.pane)")
            }
            let nested = LayoutNode.split(.horizontal, [Child(node: root, weight: 1), Child(node: .pane(Pane()), weight: 1)])
            for child in Self.children(nested.normalized()) {
                XCTAssertTrue(child.weight.isFinite && child.weight > 0, "weight \(weight) normalized to \(child.weight)")
            }
        }
    }

    // MARK: off-screen recovery

    private let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982)]

    func testAHideTheAppAppliedLateIsTold() {
        let parked = CGRect(x: 1511, y: 981, width: 800, height: 600)  // a bottom-right park corner
        XCTAssertEqual(ScanMerge.lateHide(frame: parked, minimized: false, displays: screens), .parked)
        XCTAssertEqual(ScanMerge.lateHide(frame: CGRect(x: 100, y: 100, width: 800, height: 600), minimized: true, displays: screens), .minimized)
        XCTAssertEqual(ScanMerge.lateHide(frame: CGRect(x: 100, y: 100, width: 800, height: 600), minimized: false, displays: screens), .onScreen)
    }

    private let parkedFrame = CGRect(x: 1511, y: 981, width: 800, height: 600)
    private let onScreenFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testALateHideIsAdoptedAndShownAgainWhilePaused() {
        XCTAssertEqual(ScanMerge.lateHideAction(frame: parkedFrame, minimized: false, displays: screens, managing: true), .adopt(.parked))
        XCTAssertEqual(ScanMerge.lateHideAction(frame: onScreenFrame, minimized: true, displays: screens, managing: true), .adopt(.minimized))
        // Paused: nothing re-applies visibility, so an adopted window must be shown straight away or it stays off screen.
        XCTAssertEqual(ScanMerge.lateHideAction(frame: parkedFrame, minimized: false, displays: screens, managing: false), .adoptAndShow(.parked))
        XCTAssertEqual(ScanMerge.lateHideAction(frame: onScreenFrame, minimized: true, displays: screens, managing: false), .adoptAndShow(.minimized))
        XCTAssertEqual(ScanMerge.lateHideAction(frame: onScreenFrame, minimized: false, displays: screens, managing: false), .none)
    }

    func testRestoreKeepsTheEntryOfAParkedWindowWhileItIsMinimized() {
        // Un-minimizing returns it to its park corner, so the entry is still needed.
        XCTAssertEqual(JournalRestore.step(minimized: true, parkedNow: false, entryParked: true), .keep)
        XCTAssertEqual(JournalRestore.step(minimized: true, parkedNow: false, entryParked: false), .unminimize)
        XCTAssertEqual(JournalRestore.step(minimized: true, parkedNow: false, entryParked: nil), .unminimize)
        XCTAssertEqual(JournalRestore.step(minimized: false, parkedNow: true, entryParked: true), .moveBack)
        XCTAssertEqual(JournalRestore.step(minimized: false, parkedNow: false, entryParked: true), .done)
    }

    func testARestoreCountsOnlyWhenTheWindowLandedOnScreen() {
        XCTAssertFalse(JournalRestore.landed(moved: true, frame: parkedFrame, displays: screens), "AX said yes, but the app kept it parked")
        XCTAssertFalse(JournalRestore.landed(moved: true, frame: nil, displays: screens), "no frame read back")
        XCTAssertFalse(JournalRestore.landed(moved: false, frame: onScreenFrame, displays: screens))
        XCTAssertTrue(JournalRestore.landed(moved: true, frame: onScreenFrame, displays: screens))
    }

    func testLaunchRecoveryTriesBothWhenTheEntryDoesNotSayHowItWasHidden() {
        XCTAssertEqual(JournalRestore.launchSteps(entryParked: true), [.moveBack])
        XCTAssertEqual(JournalRestore.launchSteps(entryParked: false), [.unminimize])
        // A failed hide may have landed as a park or as the minimize fallback.
        XCTAssertEqual(JournalRestore.launchSteps(entryParked: nil), [.unminimize, .moveBack])
    }

    func testSameWindowUsesTheTitleOnlyWhenNeitherSideHasANumber() {
        let numbered = JournalKey(pid: 10, windowNumber: 7, title: "Untitled")
        XCTAssertTrue(numbered.isSameWindow(JournalKey(pid: 10, windowNumber: 7, title: "Untitled 2")), "a number match survives a title change")
        XCTAssertFalse(numbered.isSameWindow(JournalKey(pid: 10, windowNumber: 8, title: "Untitled")))
        XCTAssertFalse(numbered.isSameWindow(JournalKey(pid: 10, windowNumber: nil, title: "Untitled")), "a namesake without a number")
        XCTAssertFalse(JournalKey(pid: 10, windowNumber: nil, title: "Untitled").isSameWindow(numbered))
        XCTAssertTrue(JournalKey(pid: 10, windowNumber: nil, title: "Notes").isSameWindow(JournalKey(pid: 10, windowNumber: nil, title: "Notes")))
        XCTAssertFalse(JournalKey(pid: 11, windowNumber: 7, title: "Untitled").isSameWindow(numbered), "another process")
    }

    func testTheJournalKeepsAnOlderEntryForANamesake() {
        let current = [JournalKey(pid: 10, windowNumber: 7, title: "Untitled")]
        let older = [JournalKey(pid: 10, windowNumber: nil, title: "Untitled"), JournalKey(pid: 10, windowNumber: 7, title: "Untitled")]
        XCTAssertEqual(JournalKey.withoutDuplicates(older, of: current, key: { $0 }), [older[0]], "only the same window is written once")
    }

    func testATitleOnlyEntryIsClaimedOnlyByAWindowThatIsOffScreen() {
        let titleOnly = JournalKey(pid: 10, windowNumber: nil, title: "Untitled")
        let scanned = JournalKey(pid: 10, windowNumber: 7, title: "Untitled")
        XCTAssertTrue(scanned.claims(titleOnly, entryParked: true, minimized: false, frame: parkedFrame, displays: screens))
        XCTAssertFalse(scanned.claims(titleOnly, entryParked: true, minimized: false, frame: onScreenFrame, displays: screens), "a visible namesake")
        XCTAssertFalse(scanned.claims(titleOnly, entryParked: true, minimized: true, frame: onScreenFrame, displays: screens), "minimized by the user")
        XCTAssertTrue(scanned.claims(titleOnly, entryParked: false, minimized: true, frame: onScreenFrame, displays: screens))
        let numbered = JournalKey(pid: 10, windowNumber: 7, title: "Old title")
        XCTAssertTrue(scanned.claims(numbered, entryParked: true, minimized: false, frame: onScreenFrame, displays: screens), "an exact entry")
        XCTAssertFalse(JournalKey(pid: 10, windowNumber: 9, title: "Old title").claims(numbered, entryParked: true, minimized: false,
                                                                                      frame: parkedFrame, displays: screens))
    }

    private static func children(_ node: LayoutNode?) -> [Child] {
        if case .split(_, let children)? = node { return children }
        return []
    }
}

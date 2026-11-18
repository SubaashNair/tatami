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

    private static func children(_ node: LayoutNode?) -> [Child] {
        if case .split(_, let children)? = node { return children }
        return []
    }
}

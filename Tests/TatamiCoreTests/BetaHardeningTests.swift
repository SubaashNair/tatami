import Foundation
import Testing
@testable import TatamiCore

/// Regression checks for the pre-beta bug sweep.
struct BetaHardeningTests {
    private let a = UUID(), b = UUID(), c = UUID()

    // MARK: settings file

    @Test func unreadableChoicesAndListElementsDoNotFailTheWholeSettingsFile() throws {
        var state = WorkspaceState()
        state.rules = [RoutingRule(bundleID: "com.example.mail", appName: "Mail", stageID: state.stages[1].id)]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        // What a newer build, or a hand edit, might leave behind.
        json["newWindowPlacement"] = "fromTheFuture"
        json["shortcutPreset"] = "fromTheFuture"
        json["displayChangePolicy"] = "fromTheFuture"
        json["rules"] = (json["rules"] as? [Any] ?? []) + [["broken": true]]
        json["behaviorRules"] = [["id": UUID().uuidString, "bundleID": "x", "titleContains": "", "behavior": "fromTheFuture"]]
        var stages = try #require(json["stages"] as? [[String: Any]])
        stages[0]["placement"] = "fromTheFuture"
        stages[0]["symbol"] = nil
        json["stages"] = stages

        var decoded = try JSONDecoder().decode(WorkspaceState.self, from: JSONSerialization.data(withJSONObject: json))
        try decoded.validate()
        #expect(decoded.stages.map(\.name) == state.stages.map(\.name))
        #expect(decoded.rules.map(\.bundleID) == ["com.example.mail"])
        #expect(decoded.behaviorRules.isEmpty)
        #expect(decoded.newWindowPlacement == WorkspaceState().newWindowPlacement)
        #expect(decoded.shortcutPreset == .standard)
        #expect(decoded.stages[0].placement == nil)
    }

    // MARK: windows on another Space

    @Test func aParkedWindowTheScanMissedIsKeptWhileTheWindowServerStillHasIt() {
        let known = [(id: a, pid: Int32(10), windowNumber: UInt32?(1), hidden: true),
                     (id: b, pid: Int32(10), windowNumber: UInt32?(2), hidden: true),   // closed: gone from the window server
                     (id: c, pid: Int32(10), windowNumber: UInt32?(3), hidden: true)]   // number reused by another app
        let kept = ScanMerge.keptWhileUnseen(known: known, merged: [], alive: [1: 10, 3: 99], fullScreenShowing: false)
        #expect(kept == [a])
    }

    @Test func aVisibleWindowTheScanMissedIsKeptOnlyWhileAFullScreenWindowShows() {
        // Outside full screen it was closed, or only ordered out (an app that hides its window on close): it goes.
        let known = [(id: a, pid: Int32(10), windowNumber: UInt32?(1), hidden: false), (id: b, pid: Int32(10), windowNumber: UInt32?(nil), hidden: false)]
        #expect(ScanMerge.keptWhileUnseen(known: known, merged: [], alive: [1: 10], fullScreenShowing: false).isEmpty)
        #expect(ScanMerge.keptWhileUnseen(known: known, merged: [], alive: [1: 10], fullScreenShowing: true) == [a])
        #expect(ScanMerge.keptWhileUnseen(known: known, merged: [a], alive: [1: 10], fullScreenShowing: true).isEmpty)  // seen: merged already
    }

    // MARK: AeroSpace import

    @Test func onlyTheFirstMatchingAeroSpaceRuleAppliesUnlessItChecksFurther() {
        let config = """
        [[on-window-detected]]
        if.app-id = 'com.google.Chrome'
        run = 'move-node-to-workspace 2'

        [[on-window-detected]]
        if.app-name-regex-substring = 'chrome|firefox'
        run = 'layout floating'

        [[on-window-detected]]
        if.app-id = 'org.mozilla.firefox'
        check-further-callbacks = true
        run = 'move-node-to-workspace 3'

        [[on-window-detected]]
        if.app-id = 'org.mozilla.firefox'
        run = 'layout floating'
        """
        let installed = [InstalledApp(bundleID: "com.google.Chrome", name: "Google Chrome"), InstalledApp(bundleID: "org.mozilla.firefox", name: "Firefox")]
        let rules = AeroSpaceConfig.parse(config)
        #expect(rules.map(\.checkFurther) == [false, false, true, false])
        let plan = AeroImport.plan(rules, installed: installed)
        let floated = plan.entries.filter(\.floating).flatMap(\.apps).map(\.bundleID)
        // Chrome stops at its first rule; Firefox floats from the regex rule, which also ends its search.
        #expect(floated == ["org.mozilla.firefox"])
        #expect(plan.entries.filter { $0.workspace == "3" }.isEmpty)
    }

    // MARK: AI plan

    @Test func oneMalformedActionOrSummaryDoesNotRejectTheWholePlan() throws {
        let plan = try AIPlan.parse(#"{"summary": 3, "actions": ["x", null, {"type":"createStage","name":"Focus"}]}"#)
        #expect(plan.summary == "")
        #expect(plan.actions.count == 1)
        #expect(plan.actions.first?.name == "Focus")
    }

    // MARK: pane layout

    @Test func resizingADeeplySplitPaneNeverMakesAWeightNegative() throws {
        var layout = PaneLayout.balanced(windows: [a, b], aspect: 2)
        // Each split of the last pane halves its share, so the last two end up under the minimum share.
        for _ in 0..<5 { _ = layout.split(try #require(layout.root.paneIDs.last), axis: .horizontal, moving: nil) }
        let last = try #require(layout.root.paneIDs.last)
        layout.resize(last, by: 0.3)
        layout.resize(last, by: -0.3)
        guard case .split(_, let children) = layout.root else { Issue.record("expected a row"); return }
        #expect(children.allSatisfy { $0.weight >= 0 })
        let frames = layout.frames(in: CGRect(x: 0, y: 0, width: 1000, height: 500), gap: 0, tabBar: 0)
        #expect(frames.values.allSatisfy { $0.pane.width >= 0 })
    }

    @Test func closingAPaneKeepsTheVisibleTabOfThePaneItsWindowsJoin() throws {
        var layout = PaneLayout.balanced(windows: [a, b], aspect: 2)
        let other = try #require(layout.pane(containing: b)).id
        layout.add(c, to: other)
        layout.select(a)  // the user is looking at a
        layout.removePane(other)
        let pane = try #require(layout.pane(containing: a))
        #expect(pane.selected == a)
        #expect(Set(pane.tabs) == [a, b, c])
    }

    @Test func addingToAPaneThatIsGoneLeavesTheWindowWhereItWas() throws {
        var layout = PaneLayout.balanced(windows: [a, b], aspect: 2)
        let before = try #require(layout.pane(containing: a)).id
        layout.add(a, to: UUID())
        #expect(layout.pane(containing: a)?.id == before)
        #expect(layout.root.pane(layout.focused) != nil)
    }

    @Test func aRestoredLayoutWithAStaleFocusIsRepaired() {
        var layout = PaneLayout.balanced(windows: [a, b], aspect: 2)
        layout.focused = UUID()
        layout.zoomed = UUID()
        let repaired = layout.pruned()
        #expect(repaired.root.pane(repaired.focused) != nil)
        #expect(repaired.zoomed == nil)
    }
}

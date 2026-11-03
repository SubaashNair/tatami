import XCTest
@testable import TatamiCore

/// A Room's home can be an ordered list of display preferences, first connected wins (AeroSpace's monitor lists), so one
/// setup works at home, at work and on the laptop alone.
final class HomePreferencesTests: XCTestCase {
    private var state = WorkspaceState()
    private var work: UUID { state.stages[0].id }
    private var comms: UUID { state.stages[1].id }

    private let laptop = DisplayDescriptor(key: "k-builtin", name: "Built-in Retina Display", isBuiltIn: true, isMain: true, position: 2)
    private let arzopa = DisplayDescriptor(key: "k-arzopa", name: "ARZOPA", isBuiltIn: false, isMain: false, position: 1)
    private let g27 = DisplayDescriptor(key: "k-g27", name: "G27q-20", isBuiltIn: false, isMain: false, position: 3)
    private let office = DisplayDescriptor(key: "k-office", name: "K242HYL", isBuiltIn: false, isMain: false, position: 3)
    private var home: [DisplayDescriptor] { [arzopa, laptop, g27] }
    private var workplace: [DisplayDescriptor] { [laptop, office] }

    // MARK: matching

    func testEachKindOfPreferenceMatchesItsDisplay() {
        XCTAssertTrue(DisplayPreference.key("k-g27").matches(g27))
        XCTAssertFalse(DisplayPreference.key("k-g27").matches(arzopa))
        XCTAssertTrue(DisplayPreference.pattern("g27q").matches(g27), "a name pattern ignores case and matches anywhere")
        XCTAssertTrue(DisplayPreference.pattern("^arzopa$").matches(arzopa))
        XCTAssertFalse(DisplayPreference.pattern("^arzopa$").matches(g27))
        XCTAssertTrue(DisplayPreference.builtIn.matches(laptop))
        XCTAssertFalse(DisplayPreference.builtIn.matches(g27))
        XCTAssertTrue(DisplayPreference.main.matches(laptop))
        XCTAssertTrue(DisplayPreference.secondary.matches(g27))
        XCTAssertFalse(DisplayPreference.secondary.matches(laptop))
        XCTAssertTrue(DisplayPreference.position(1).matches(arzopa))
        XCTAssertFalse(DisplayPreference.position(1).matches(laptop))
        XCTAssertFalse(DisplayPreference.pattern("([").matches(g27), "a broken pattern matches nothing")
    }

    // MARK: first connected wins

    func testTheFirstConnectedChoiceWins() {
        _ = state.setHomeFallbacks([.pattern("s24f350"), .pattern("g27q"), .pattern("k242hyl"), .main], for: work)
        state.perDisplayRooms = true
        XCTAssertEqual(state.effectiveHome(of: work, displays: home), "k-g27", "at home: g27q")
        XCTAssertEqual(state.effectiveHome(of: work, displays: workplace), "k-office", "at work: k242hyl")
        XCTAssertEqual(state.effectiveHome(of: work, displays: [laptop]), "k-builtin", "laptop alone: main, the last resort")
    }

    func testAPickedDisplayComesBeforeTheFallbacks() {
        _ = state.setHomeFallbacks([.pattern("g27q")], for: work)
        state.stages[0].homeDisplay = "k-arzopa"
        state.perDisplayRooms = true
        XCTAssertEqual(state.effectiveHome(of: work, displays: home), "k-arzopa")
        XCTAssertEqual(state.effectiveHome(of: work, displays: [laptop, g27]), "k-g27", "the picked display is unplugged")
    }

    func testNoChoiceConnectedMeansNoHome() {
        _ = state.setHomeFallbacks([.pattern("g27q")], for: work)
        state.perDisplayRooms = true
        XCTAssertNil(state.effectiveHome(of: work, displays: [laptop]))
    }

    func testHomesAreIgnoredWithPerDisplayRoomsOff() {
        _ = state.setHomeFallbacks([.main], for: work)
        state.perDisplayRooms = false
        XCTAssertNil(state.effectiveHome(of: work, displays: home))
    }

    func testARoomWithOnlyPreferencesHasAHomeAndOpensItsWindowsAsTabs() {
        _ = state.setHomeFallbacks([.pattern("g27q")], for: work)
        XCTAssertTrue(state.hasHome(work))
        XCTAssertFalse(state.hasHome(comms))
        state.newWindowPlacement = .automatic
        XCTAssertEqual(state.placement(forRoom: work), .active)
    }

    func testSettingPreferencesTurnsOnPerDisplayRooms() {
        XCTAssertFalse(state.perDisplayRooms)
        XCTAssertTrue(state.setHomeFallbacks([.main], for: work))
        XCTAssertTrue(state.perDisplayRooms)
        XCTAssertFalse(state.setHomeFallbacks([.main], for: UUID()), "an unknown Room")
    }

    // MARK: routing and applying

    func testARoutedWindowGoesToTheResolvedDisplay() {
        _ = state.setHomeFallbacks([.pattern("g27q"), .pattern("k242hyl")], for: comms)
        state.rules = [RoutingRule(bundleID: "slack", appName: "Slack", stageID: comms)]
        XCTAssertEqual(state.routedTarget(bundleID: "slack", title: "", displays: home), RoutedTarget(room: comms, display: "k-g27"))
        XCTAssertEqual(state.routedTarget(bundleID: "slack", title: "", displays: workplace), RoutedTarget(room: comms, display: "k-office"))
        XCTAssertEqual(state.homeToMoveTo(room: comms, currentDisplay: "k-builtin", displays: home), "k-g27")
        XCTAssertNil(state.homeToMoveTo(room: comms, currentDisplay: "k-g27", displays: home))
    }

    func testApplyingHomesPutsEachResolvedRoomOnItsDisplayWithoutOverridingYourChoice() {
        _ = state.setHomeFallbacks([.pattern("g27q")], for: work)
        _ = state.setHomeFallbacks([.builtIn], for: comms)
        state.displayRooms = [:]
        state.activeStageID = state.stages[2].id
        state.applyHomes(displays: home)
        XCTAssertEqual(state.activeRoomID(on: "k-g27"), work)
        XCTAssertEqual(state.activeRoomID(on: "k-builtin"), comms)
        state.displayRooms["k-g27"] = state.stages[2].id  // you switched it yourself
        state.applyHomes(displays: home)
        XCTAssertEqual(state.activeRoomID(on: "k-g27"), state.stages[2].id)
    }

    func testTheHomeIsShowingOnlyWhenItsDisplayShowsTheRoom() {
        _ = state.setHomeFallbacks([.pattern("g27q")], for: work)
        state.displayRooms["k-g27"] = comms
        XCTAssertFalse(state.homeIsShowing(work, displays: home))
        state.displayRooms["k-g27"] = work
        XCTAssertTrue(state.homeIsShowing(work, displays: home))
    }

    // MARK: saving and cleaning up

    func testPreferencesSurviveASaveAndLoadAndOlderRoomsStillLoad() throws {
        _ = state.setHomeFallbacks([.pattern("g27q"), .builtIn, .position(2), .key("x")], for: work)
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(loaded.stages[0].homeFallbacks, [.pattern("g27q"), .builtIn, .position(2), .key("x")])
        let old = Data(#"{"id":"\#(UUID().uuidString)","name":"Work","symbol":"x"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Stage.self, from: old).homeFallbacks, [])
    }

    func testValidationLimitsTheListAndTheLengthOfAPattern() throws {
        _ = state.setHomeFallbacks(Array(repeating: .main, count: 20), for: work)
        state.stages[0].homeFallbacks.append(.pattern(String(repeating: "x", count: 500)))
        try state.validate()
        XCTAssertLessThanOrEqual(state.stages[0].homeFallbacks.count, 8)
        XCTAssertFalse(state.stages[0].homeFallbacks.contains(.pattern(String(repeating: "x", count: 500))))
    }

    func testMergingAllRoomsClearsTheSurvivorsPreferences() {
        _ = state.setHomeFallbacks([.main], for: work)
        _ = state.mergeAll()
        XCTAssertTrue(state.stages[0].homeFallbacks.isEmpty)
    }

    // MARK: reading AeroSpace's monitor assignments

    func testItReadsTheMonitorListsOfAnAeroSpaceConfig() {
        let text = """
        [gaps]
            inner.horizontal = 8

        [workspace-to-monitor-force-assignment]
        # Only S stays pinned.
        # 1 = ['built-in', 'main']        # commented out
        S = ['s24f350', 'g27q', 'k242hyl', 'main']   # Samsung: Chrome only
        C = 'built-in'
        2 = [1, 'secondary']
        W = ['arzopa', 'Secondary']

        [[on-window-detected]]
        if.app-id = 'x.y'
        run = 'move-node-to-workspace S'
        """
        let monitors = AeroSpaceConfig.parseMonitorAssignments(text)
        XCTAssertEqual(monitors["S"], [.pattern("s24f350"), .pattern("g27q"), .pattern("k242hyl"), .main])
        XCTAssertEqual(monitors["C"], [.builtIn])
        XCTAssertEqual(monitors["2"], [.position(1), .secondary])
        XCTAssertEqual(monitors["W"], [.pattern("arzopa"), .secondary], "keywords ignore case")
        XCTAssertNil(monitors["1"], "a commented line is not an assignment")
        XCTAssertEqual(monitors.count, 4)
    }

    func testAFileWithoutThatSectionHasNoAssignments() {
        XCTAssertTrue(AeroSpaceConfig.parseMonitorAssignments("[gaps]\ninner = 8\n").isEmpty)
    }

    func testTheImportAppliesTheMonitorListsToTheRoomsItCreates() {
        let installed = [InstalledApp(bundleID: "com.google.Chrome", name: "Google Chrome")]
        let rules = [AeroRule(appID: "com.google.Chrome", nameRegex: nil, workspace: "S", floating: false, unsupported: [])]
        let monitors: [String: [DisplayPreference]] = ["S": [.pattern("g27q"), .main], "Q": [.main]]
        let plan = AeroImport.plan(rules, installed: installed, monitors: monitors)
        XCTAssertEqual(plan.monitors, ["S": [.pattern("g27q"), .main]], "only the workspaces that become Rooms")
        let result = state.applyAeroImport(plan, roomNames: ["S": "Search"])
        let search = state.stages.first { $0.name == "Search" }!
        XCTAssertEqual(search.homeFallbacks, [.pattern("g27q"), .main])
        XCTAssertFalse(state.perDisplayRooms, "an import never changes how your displays show Rooms by itself")
        XCTAssertEqual(result.homesSet, 1)
        XCTAssertTrue(result.needsPerDisplayRooms, "but it says the homes need that mode")
    }

    func testAnImportNeverOverwritesAHomeYouSet() {
        _ = state.setHome("k-g27", for: work, displays: [])
        let installed = [InstalledApp(bundleID: "x.y", name: "X")]
        let rules = [AeroRule(appID: "x.y", nameRegex: nil, workspace: "S", floating: false, unsupported: [])]
        let plan = AeroImport.plan(rules, installed: installed, monitors: ["S": [.main]])
        let result = state.applyAeroImport(plan, roomNames: ["S": "Work"])
        XCTAssertEqual(state.stages[0].homeDisplay, "k-g27")
        XCTAssertTrue(state.stages[0].homeFallbacks.isEmpty)
        XCTAssertEqual(result.homesSet, 0)
    }

    // MARK: clearing, swapping and ordering

    func testNoneClearsThePickedDisplayAndTheWholeList() {
        _ = state.setHome("k-g27", for: work, displays: [])
        _ = state.setHomeFallbacks([.main], for: work)
        XCTAssertTrue(state.setHome(nil, for: work, displays: []))
        XCTAssertFalse(state.hasHome(work))
        XCTAssertTrue(state.stages[0].homeFallbacks.isEmpty)
    }

    func testSendingARoomMovesItsHomeEvenWhenTheHomeCameFromThePreferenceList() {
        state.perDisplayRooms = true
        _ = state.setHomeFallbacks([.pattern("g27q")], for: work)
        let displays = home
        state.displayRooms = ["k-g27": work, "k-builtin": comms, "k-arzopa": state.stages[2].id]
        let swap = state.swapRooms(between: "k-g27", and: "k-builtin", displays: displays)
        XCTAssertNotNil(swap)
        XCTAssertEqual(state.effectiveHome(of: work, displays: displays), "k-builtin", "Work now lives where it was sent")
    }

    func testTheLowestPositionWinsWhateverOrderTheDisplaysAreListedIn() {
        _ = state.setHomeFallbacks([.secondary], for: work)
        state.perDisplayRooms = true
        let shuffled = [g27, laptop, arzopa]  // arzopa is position 1, g27 is 3
        XCTAssertEqual(state.effectiveHome(of: work, displays: shuffled), "k-arzopa")
        XCTAssertEqual(state.effectiveHome(of: work, displays: shuffled.reversed()), "k-arzopa")
    }

    func testAnInvalidListIsReportedNotCountedAsAHome() {
        XCTAssertFalse(state.setHomeFallbacks([.pattern(String(repeating: "x", count: 300))], for: work))
        XCTAssertFalse(state.hasHome(work))
    }

    func testAnUnknownFutureChoiceDoesNotCostYouYourSettings() throws {
        _ = state.setHomeFallbacks([.main], for: work)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        var stages = object["stages"] as! [[String: Any]]
        stages[0]["homeFallbacks"] = [["somethingNew": ["_0": 1]], ["main": [String: Any]()]]
        object["stages"] = stages
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(loaded.stages[0].homeFallbacks, [.main], "the choice we cannot read is dropped, the rest stays")
    }

    // MARK: monitor assignment parsing details

    func testNumbersAreOnlyPositionsWhenUnquotedAndInRange() {
        let text = "[workspace-to-monitor-force-assignment]\nA = [1, 40, '27']\n"
        XCTAssertEqual(AeroSpaceConfig.parseMonitorAssignments(text)["A"], [.position(1), .pattern("27")], "40 is dropped, a quoted number is a name")
    }

    func testBracketsInsideQuotesAndMultiLineListsAreRead() {
        let text = """
        [ workspace-to-monitor-force-assignment ]
        A = ['a]b', 'c']
        B = [
            'one',   # first
            'two',
        ]
        C = 'main'
        """
        let monitors = AeroSpaceConfig.parseMonitorAssignments(text)
        XCTAssertEqual(monitors["A"], [.pattern("a]b"), .pattern("c")])
        XCTAssertEqual(monitors["B"], [.pattern("one"), .pattern("two")])
        XCTAssertEqual(monitors["C"], [.main])
    }

    func testWindowsLineEndingsWorkForMonitorAssignments() {
        let text = "[workspace-to-monitor-force-assignment]\r\nA = ['g27q', 'main']\r\n"
        XCTAssertEqual(AeroSpaceConfig.parseMonitorAssignments(text)["A"], [.pattern("g27q"), .main])
    }
}

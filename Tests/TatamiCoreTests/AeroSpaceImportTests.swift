import XCTest
@testable import TatamiCore

/// Importing `[[on-window-detected]]` rules from an AeroSpace config: workspaces become Rooms, apps become routing rules.
final class AeroSpaceImportTests: XCTestCase {
    private let sample = """
    config-version = 2
    start-at-login = true

    [gaps]
        inner.horizontal = 8

    [[on-window-detected]]
    if.app-id = 'com.google.Chrome'
    run = 'move-node-to-workspace S'

    [[on-window-detected]]
    if.app-name-regex-substring = '^(iTerm2|Warp|Visual Studio Code|Xcode|Claude)$'  # coding
    run = "move-node-to-workspace C"

    # a comment between rules
    [[on-window-detected]]
    if.app-name-regex-substring = '^(Spotify|Music)$'
    run = ['layout tiling', 'move-node-to-workspace P']

    [[on-window-detected]]
    if.app-id = 'com.apple.systempreferences'
    run = 'layout floating'

    [mode.main.binding]
        alt-1 = 'workspace 1'
    """

    // MARK: parsing

    func testItReadsEveryOnWindowDetectedRuleAndNothingElse() {
        let rules = AeroSpaceConfig.parse(sample)
        XCTAssertEqual(rules.count, 4)
        XCTAssertEqual(rules[0], AeroRule(appID: "com.google.Chrome", nameRegex: nil, workspace: "S", floating: false, unsupported: []))
        XCTAssertEqual(rules[1].nameRegex, "^(iTerm2|Warp|Visual Studio Code|Xcode|Claude)$", "the trailing comment is dropped")
        XCTAssertEqual(rules[1].workspace, "C", "double quotes work too")
    }

    func testARunArrayKeepsTheWorkspaceAndIgnoresOtherCommands() {
        XCTAssertEqual(AeroSpaceConfig.parse(sample)[2].workspace, "P")
    }

    func testLayoutFloatingBecomesAFloatRule() {
        let rule = AeroSpaceConfig.parse(sample)[3]
        XCTAssertTrue(rule.floating)
        XCTAssertNil(rule.workspace)
    }

    func testAMultiLineRunArrayIsRead() {
        let text = """
        [[on-window-detected]]
        if.app-id = 'x.y'
        run = [
            'layout tiling',   # comment
            'move-node-to-workspace --focus-follows-window M',
        ]
        """
        XCTAssertEqual(AeroSpaceConfig.parse(text).first?.workspace, "M")
    }

    func testUnsupportedConditionsAreRecordedNotSilentlyDropped() {
        let text = """
        [[on-window-detected]]
        if.app-id = 'x.y'
        if.window-title-regex-substring = 'Picture'
        run = 'move-node-to-workspace A'
        """
        let rule = AeroSpaceConfig.parse(text)[0]
        XCTAssertEqual(rule.unsupported, ["if.window-title-regex-substring"])
    }

    func testAnEmptyOrUnrelatedFileGivesNoRules() {
        XCTAssertTrue(AeroSpaceConfig.parse("").isEmpty)
        XCTAssertTrue(AeroSpaceConfig.parse("[gaps]\ninner.horizontal = 8\n").isEmpty)
    }

    func testAHashInsideQuotesIsNotAComment() {
        let text = "[[on-window-detected]]\nif.app-name-regex-substring = 'C#'\nrun = 'move-node-to-workspace A'\n"
        XCTAssertEqual(AeroSpaceConfig.parse(text).first?.nameRegex, "C#")
    }

    // MARK: matching names

    func testNamePatternsMatchLikeAeroSpaceCaseInsensitiveAndAnywhere() {
        let pattern = "^(Slack|.?WhatsApp|Discord|zoom\\.us|Mail|Notion)$"
        for name in ["Slack", "slack", "\u{200E}WhatsApp", "WhatsApp", "zoom.us", "Mail", "Notion"] {
            XCTAssertTrue(AeroNameMatcher.matches(pattern, name: name), name)
        }
        for name in ["Mailspring", "Slack Helper", "zoomXus"] {
            XCTAssertFalse(AeroNameMatcher.matches(pattern, name: name), name)
        }
        XCTAssertTrue(AeroNameMatcher.matches("Code", name: "Visual Studio Code"), "a substring match when not anchored")
    }

    func testABrokenPatternMatchesNothingInsteadOfCrashing() {
        XCTAssertFalse(AeroNameMatcher.matches("([", name: "Anything"))
    }

    // MARK: the plan

    private let installed = [
        InstalledApp(bundleID: "com.google.Chrome", name: "Google Chrome"),
        InstalledApp(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code"),
        InstalledApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
        InstalledApp(bundleID: "com.spotify.client", name: "Spotify"),
        InstalledApp(bundleID: "com.apple.systempreferences", name: "System Settings"),
    ]

    func testThePlanListsRoomsInFirstSeenOrderAndResolvesAppNames() {
        let plan = AeroImport.plan(AeroSpaceConfig.parse(sample), installed: installed)
        XCTAssertEqual(plan.rooms, ["S", "C", "P"])
        let coding = plan.entries[1]
        XCTAssertEqual(Set(coding.apps.map(\.bundleID)), ["com.microsoft.VSCode", "com.apple.dt.Xcode"])
        XCTAssertEqual(coding.workspace, "C")
        XCTAssertEqual(plan.entries[0].apps.map(\.bundleID), ["com.google.Chrome"], "an app id needs no lookup")
    }

    func testAnAppListedUnderTwoNamesIsPlannedOnce() {
        let twice = installed + [InstalledApp(bundleID: "com.apple.dt.Xcode", name: "Xcode.app")]
        let rules = [AeroRule(appID: nil, nameRegex: "Xcode", workspace: "C", floating: false, unsupported: [])]
        XCTAssertEqual(AeroImport.plan(rules, installed: twice).entries[0].apps.count, 1)
    }

    // MARK: reader details

    func testDoubleQuotedStringsAreUnescaped() {
        let text = "[[on-window-detected]]\nif.app-name-regex-substring = \"^zoom\\\\.us$\"\nrun = 'move-node-to-workspace M'\n"
        XCTAssertEqual(AeroSpaceConfig.parse(text).first?.nameRegex, "^zoom\\.us$")
    }

    func testAnUnclosedArrayDoesNotSwallowTheNextRule() {
        let text = """
        [[on-window-detected]]
        if.app-id = 'a.b'
        run = ['move-node-to-workspace A'

        [[on-window-detected]]
        if.app-id = 'c.d'
        run = 'move-node-to-workspace B'
        """
        let rules = AeroSpaceConfig.parse(text)
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules[1].appID, "c.d")
        XCTAssertEqual(rules[1].workspace, "B")
    }

    func testWindowsLineEndingsWork() {
        let text = sample.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(AeroSpaceConfig.parse(text).count, 4)
    }

    func testRelativeWorkspaceTargetsAreNotRooms() {
        let text = "[[on-window-detected]]\nif.app-id = 'a.b'\nrun = 'move-node-to-workspace next'\n"
        XCTAssertNil(AeroSpaceConfig.parse(text).first?.workspace)
    }

    func testRoomNamesAreCheckedBeforeImporting() {
        let plan = AeroImport.plan(AeroSpaceConfig.parse(sample), installed: installed)
        XCTAssertNil(AeroImport.nameProblem(plan: plan, roomNames: ["S": "Search", "C": "Code", "P": "Media"]))
        XCTAssertNotNil(AeroImport.nameProblem(plan: plan, roomNames: ["S": "  ", "C": "Code", "P": "Media"]), "empty")
        XCTAssertNotNil(AeroImport.nameProblem(plan: plan, roomNames: ["S": String(repeating: "x", count: 61), "C": "Code", "P": "Media"]), "too long")
        XCTAssertNotNil(AeroImport.nameProblem(plan: plan, roomNames: ["S": "Code", "C": "code", "P": "Media"]), "two workspaces, one name")
    }

    // MARK: undo and conflicts

    func testRoutingRulesForRemovedRoomsAreDroppedWhenSaving() throws {
        var state = WorkspaceState()
        let plan = AeroImport.plan(AeroSpaceConfig.parse(sample), installed: installed)
        let before = state.stages
        _ = state.applyAeroImport(plan, roomNames: ["S": "Search", "C": "Code", "P": "Media"])
        state.stages = before  // what undo does to the Rooms
        try state.validate()
        XCTAssertTrue(state.rules.isEmpty, "no rule may point at a Room that is gone")
        let again = state.applyAeroImport(plan, roomNames: ["S": "Search", "C": "Code", "P": "Media"])
        XCTAssertGreaterThan(again.rulesAdded, 0, "importing again works after an undo")
    }

    func testADisabledRuleDoesNotBlockAnImport() {
        var state = WorkspaceState()
        var rule = RoutingRule(bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", stageID: state.stages[0].id)
        rule.enabled = false
        state.rules = [rule]
        let plan = AeroImport.plan(AeroSpaceConfig.parse(sample), installed: installed)
        let result = state.applyAeroImport(plan, roomNames: ["S": "Search", "C": "Code", "P": "Media"])
        XCTAssertEqual(result.keptExisting, 0)
        XCTAssertNotNil(state.destination(bundleID: "com.microsoft.VSCode", title: ""))
    }

    func testTheRuleLimitIsReportedNotSilentlyHit() {
        var state = WorkspaceState()
        state.rules = (0..<500).map { RoutingRule(bundleID: "filler.\($0)", appName: "x", stageID: state.stages[0].id) }
        let plan = AeroImport.plan(AeroSpaceConfig.parse(sample), installed: installed)
        let result = state.applyAeroImport(plan, roomNames: ["S": "Search", "C": "Code", "P": "Media"])
        XCTAssertEqual(state.rules.count, 500)
        XCTAssertTrue(result.skipped.contains { $0.contains("500") })
    }

    func testAnAppAlreadyRoutedByAnEarlierRuleOfTheSameImportIsNotCountedAsYours() {
        var state = WorkspaceState()
        let rules = [
            AeroRule(appID: "x.y", nameRegex: nil, workspace: "A", floating: false, unsupported: []),
            AeroRule(appID: "x.y", nameRegex: nil, workspace: "B", floating: false, unsupported: []),
        ]
        let result = state.applyAeroImport(AeroImport.plan(rules, installed: []), roomNames: [:])
        XCTAssertEqual(result.rulesAdded, 1)
        XCTAssertEqual(result.keptExisting, 0, "that is the import's own first rule, not one of yours")
    }

    func testAnAppIdThatIsNotInstalledIsStillKept() {
        let rules = [AeroRule(appID: "com.gone.App", nameRegex: nil, workspace: "A", floating: false, unsupported: [])]
        let plan = AeroImport.plan(rules, installed: installed)
        XCTAssertEqual(plan.entries[0].apps, [InstalledApp(bundleID: "com.gone.App", name: "com.gone.App")])
    }

    func testAPatternThatMatchesNoInstalledAppIsSkippedAndCreatesNoEmptyRoom() {
        let rules = [AeroRule(appID: nil, nameRegex: "^Nothing$", workspace: "A", floating: false, unsupported: [])]
        let plan = AeroImport.plan(rules, installed: installed)
        XCTAssertTrue(plan.entries.isEmpty)
        XCTAssertTrue(plan.rooms.isEmpty, "no apps, so no Room")
        XCTAssertEqual(plan.skipped.count, 1)
        XCTAssertTrue(plan.skipped[0].contains("^Nothing$"))
    }

    func testABrokenOrHugePatternIsReportedAsInvalid() {
        let broken = [AeroRule(appID: nil, nameRegex: "([", workspace: "A", floating: false, unsupported: [])]
        XCTAssertTrue(AeroImport.plan(broken, installed: installed).skipped[0].contains("not a valid pattern"))
        let huge = [AeroRule(appID: nil, nameRegex: String(repeating: "a", count: 600), workspace: "A", floating: false, unsupported: [])]
        XCTAssertTrue(AeroImport.plan(huge, installed: installed).skipped[0].contains("not a valid pattern"))
    }

    func testMoreThanNineWorkspacesStopAtNineRooms() {
        let rules = (1...12).map { AeroRule(appID: "app.\($0)", nameRegex: nil, workspace: "W\($0)", floating: false, unsupported: []) }
        let plan = AeroImport.plan(rules, installed: [])
        XCTAssertEqual(plan.rooms.count, 9)
        XCTAssertEqual(plan.entries.count, 9)
        XCTAssertEqual(plan.skipped.count, 3, "the rules for the last three workspaces")
    }

    func testRulesWithUnsupportedConditionsOrNoActionAreSkippedWithAReason() {
        let rules = [
            AeroRule(appID: "a.b", nameRegex: nil, workspace: "A", floating: false, unsupported: ["if.window-title-regex-substring"]),
            AeroRule(appID: "c.d", nameRegex: nil, workspace: nil, floating: false, unsupported: []),
        ]
        let plan = AeroImport.plan(rules, installed: [])
        XCTAssertTrue(plan.entries.isEmpty)
        XCTAssertEqual(plan.skipped.count, 2)
        XCTAssertTrue(plan.skipped[0].contains("if.window-title-regex-substring"))
    }

    // MARK: applying it

    func testApplyingCreatesRoomsRoutingRulesAndFloatRules() {
        var state = WorkspaceState()
        state.stages = [Stage(name: "Work")]
        let plan = AeroImport.plan(AeroSpaceConfig.parse(sample), installed: installed)
        let result = state.applyAeroImport(plan, roomNames: ["S": "Search", "C": "Code", "P": "Media"])
        XCTAssertEqual(state.stages.map(\.name), ["Work", "Search", "Code", "Media"])
        XCTAssertEqual(result.roomsCreated, ["Search", "Code", "Media"])
        let code = state.stages.first { $0.name == "Code" }!.id
        XCTAssertEqual(state.destination(bundleID: "com.microsoft.VSCode", title: ""), code)
        XCTAssertEqual(state.destination(bundleID: "com.apple.dt.Xcode", title: ""), code)
        XCTAssertTrue(state.isFloating(bundleID: "com.apple.systempreferences", title: ""))
        XCTAssertTrue(state.behaviorRules.contains { $0.bundleID == "com.apple.systempreferences" && $0.behavior == .floating })
    }

    func testAnExistingRoomWithTheSameNameIsReusedNotDuplicated() {
        var state = WorkspaceState()
        state.stages = [Stage(name: "Code")]
        let plan = AeroImport.plan(AeroSpaceConfig.parse(sample), installed: installed)
        let result = state.applyAeroImport(plan, roomNames: ["C": "code", "S": "Search", "P": "Media"])
        XCTAssertEqual(state.stages.filter { $0.name.lowercased() == "code" }.count, 1)
        XCTAssertFalse(result.roomsCreated.contains("code"))
    }

    func testImportingTwiceAddsNothingTheSecondTime() {
        var state = WorkspaceState()
        let plan = AeroImport.plan(AeroSpaceConfig.parse(sample), installed: installed)
        _ = state.applyAeroImport(plan, roomNames: ["S": "Search", "C": "Code", "P": "Media"])
        let rules = state.rules.count, floats = state.behaviorRules.count, rooms = state.stages.count
        let again = state.applyAeroImport(plan, roomNames: ["S": "Search", "C": "Code", "P": "Media"])
        XCTAssertEqual(state.rules.count, rules)
        XCTAssertEqual(state.behaviorRules.count, floats)
        XCTAssertEqual(state.stages.count, rooms)
        XCTAssertEqual(again.rulesAdded, 0)
    }

    func testAnAppAlreadyRoutedElsewhereKeepsItsExistingRule() {
        var state = WorkspaceState()
        let existing = state.stages[0].id
        state.rules = [RoutingRule(bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", stageID: existing)]
        let plan = AeroImport.plan(AeroSpaceConfig.parse(sample), installed: installed)
        let result = state.applyAeroImport(plan, roomNames: ["S": "Search", "C": "Code", "P": "Media"])
        XCTAssertEqual(state.destination(bundleID: "com.microsoft.VSCode", title: ""), existing, "your own rule wins")
        XCTAssertGreaterThan(result.keptExisting, 0)
    }

    func testWhenTheRoomLimitIsReachedItsRulesAreSkippedNotLost() {
        var state = WorkspaceState()
        state.stages = (1...9).map { Stage(name: "R\($0)") }
        let plan = AeroImport.plan(AeroSpaceConfig.parse(sample), installed: installed)
        let result = state.applyAeroImport(plan, roomNames: ["S": "Search", "C": "Code", "P": "Media"])
        XCTAssertEqual(state.stages.count, 9)
        XCTAssertTrue(result.roomsCreated.isEmpty)
        XCTAssertFalse(result.skipped.isEmpty)
        XCTAssertTrue(state.rules.isEmpty, "no Room to send the apps to, so no rules")
    }
}

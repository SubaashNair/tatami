import XCTest
import CoreGraphics
@testable import TatamiCore

final class AIPlanTests: XCTestCase {
    private let context = PlanContext(
        windows: [PlanWindow(ref: "w1", appName: "Xcode", bundleID: "com.apple.dt.Xcode", title: "Tatami.xcodeproj", stageName: "Work", display: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
                  PlanWindow(ref: "w2", appName: "Slack", bundleID: "com.tinyspeck.slackmacgap", title: "Acme secret channel", stageName: "Work", display: 1, frame: CGRect(x: 0, y: 0, width: 600, height: 500))],
        stageNames: ["Work", "Comms"],
        displays: [CGSize(width: 1512, height: 944), CGSize(width: 2560, height: 1440)])

    // MARK: parse

    func testParsesBareJSON() throws {
        let plan = try AIPlan.parse(#"{"summary":"s","actions":[{"type":"assign","window":"w1","stage":"Comms"}]}"#)
        XCTAssertEqual(plan.summary, "s")
        XCTAssertEqual(plan.actions.first?.type, "assign")
    }

    func testParsesFencedJSONAfterProse() throws {
        let text = """
        Sure! Here is the plan:
        ```json
        {"summary":"Uses {braces} in text","actions":[{"type":"createStage","name":"Build \\"B\\""}]}
        ```
        Hope that helps {not json}.
        """
        let plan = try AIPlan.parse(text)
        XCTAssertEqual(plan.summary, "Uses {braces} in text")
        XCTAssertEqual(plan.actions.first?.name, #"Build "B""#)
    }

    func testRejectsTextWithoutJSON() {
        XCTAssertThrowsError(try AIPlan.parse("I cannot do that.")) { XCTAssertEqual($0 as? AIPlanError, .noJSON) }
        XCTAssertThrowsError(try AIPlan.parse(#"{"summary": "unterminated"#)) { XCTAssertEqual($0 as? AIPlanError, .noJSON) }
    }

    func testRejectsMalformedPlanShape() {
        XCTAssertThrowsError(try AIPlan.parse(#"{"actions":"nope"}"#)) { XCTAssertEqual($0 as? AIPlanError, .invalidShape) }
    }

    // MARK: validate

    func testCreateThenUseStageInSamePlan() throws {
        let plan = try AIPlan.parse(#"{"summary":"","actions":[{"type":"createStage","name":"Build"},{"type":"assign","window":"w1","stage":"build"}]}"#)
        let result = plan.validate(against: context)
        XCTAssertEqual(result.valid, [.createStage(name: "Build"), .assign(window: "w1", stage: "Build")])
        XCTAssertTrue(result.dropped.isEmpty)
    }

    func testDroppedCreateCascadesToDependents() throws {
        let long = String(repeating: "x", count: 61)
        let plan = try AIPlan.parse(#"{"summary":"","actions":[{"type":"createStage","name":"\#(long)"},{"type":"assign","window":"w1","stage":"\#(long)"},{"type":"snap","window":"w1","zone":"left"}]}"#)
        let result = plan.validate(against: context)
        XCTAssertEqual(result.valid, [.snap(window: "w1", zone: .left, display: nil)])
        XCTAssertEqual(result.dropped.count, 2)
        XCTAssertTrue(result.dropped[1].reason.contains("was not created"))
    }

    func testRejectsUnknownRefsZonesDisplaysAndTypes() throws {
        let plan = try AIPlan.parse(#"""
        {"summary":"","actions":[
          {"type":"assign","window":"w9","stage":"Work"},
          {"type":"assign","window":"w1","stage":"Nowhere"},
          {"type":"snap","window":"w1","zone":"diagonal"},
          {"type":"snap","window":"w1","zone":"right","display":3},
          {"type":"snap","window":"w2","zone":"maximize","display":2},
          {"type":"closeApp","window":"w1"},
          {"type":"assign"}
        ]}
        """#)
        let result = plan.validate(against: context)
        XCTAssertEqual(result.valid, [.snap(window: "w2", zone: .maximize, display: 2)])
        XCTAssertEqual(result.dropped.count, 6)
    }

    func testStageLimitAndDuplicateNames() throws {
        let creates = (1...8).map { #"{"type":"createStage","name":"S\#($0)"}"# }.joined(separator: ",")
        let plan = try AIPlan.parse(#"{"summary":"","actions":[{"type":"createStage","name":"comms"},\#(creates)]}"#)
        let result = plan.validate(against: context)
        XCTAssertEqual(result.valid.count, 7) // 2 existing + 7 = 9
        XCTAssertEqual(result.dropped.count, 2)
        XCTAssertTrue(result.dropped[0].reason.contains("already exists"))
    }

    func testRenameUpdatesLaterReferences() throws {
        let plan = try AIPlan.parse(#"{"summary":"","actions":[{"type":"renameStage","from":"Comms","to":"Chat"},{"type":"assign","window":"w2","stage":"Chat"},{"type":"assign","window":"w1","stage":"Comms"}]}"#)
        let result = plan.validate(against: context)
        XCTAssertEqual(result.valid, [.renameStage(from: "Comms", to: "Chat"), .assign(window: "w2", stage: "Chat")])
        XCTAssertEqual(result.dropped.count, 1)
    }

    func testActionCap() throws {
        let many = Array(repeating: #"{"type":"snap","window":"w1","zone":"left"}"#, count: AIPlan.maxActions + 5).joined(separator: ",")
        let result = try AIPlan.parse(#"{"summary":"","actions":[\#(many)]}"#).validate(against: context)
        XCTAssertEqual(result.valid.count, AIPlan.maxActions)
        XCTAssertEqual(result.dropped.count, 5)
    }

    // MARK: prompt

    func testPromptIncludesRefsAndOmitsTitlesWhenDisabled() {
        let with = AIPrompt.user(request: "tidy up", context: context, includeTitles: true, previousSummary: nil)
        XCTAssertTrue(with.contains("w1") && with.contains("Xcode") && with.contains("Comms") && with.contains("Acme secret channel"))
        let without = AIPrompt.user(request: "tidy up", context: context, includeTitles: false, previousSummary: "Earlier plan")
        XCTAssertTrue(without.contains("w2") && without.contains("Slack"))
        XCTAssertFalse(without.contains("Acme secret channel"))
        XCTAssertTrue(without.contains("Earlier plan"))
    }

    func testSystemPromptListsEveryZone() {
        for zone in SnapZone.allCases { XCTAssertTrue(AIPrompt.system.contains(zone.rawValue)) }
    }
}

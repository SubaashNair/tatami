import XCTest
@testable import TatamiCore

final class StagesTests: XCTestCase {
    func testMergeAllKeepsOnlyTheFirstStage() throws {
        var state = WorkspaceState()
        let first = state.stages[0].id
        state.activeStageID = state.stages[2].id
        XCTAssertEqual(state.mergeAll(), first)
        XCTAssertEqual(state.stages.map(\.id), [first])
        XCTAssertEqual(state.activeStageID, first)
        try state.validate()
    }

    func testCycleWrapsInBothDirections() {
        let state = WorkspaceState()
        let ids = state.stages.map(\.id)
        XCTAssertEqual(state.stageID(offset: 1), ids[1])
        XCTAssertEqual(state.stageID(offset: -1), ids[2])
        XCTAssertEqual(state.stageID(offset: 3), ids[0])
    }

    func testNextStageNameSkipsTakenNames() {
        var state = WorkspaceState()
        XCTAssertEqual(state.nextStageName(), "Room 4")
        state.addStage(name: "Room 4")
        XCTAssertEqual(state.nextStageName(), "Room 5")
    }

    func testCategoriesClassifyKnownApps() {
        XCTAssertEqual(StageCategory.classify("com.tinyspeck.slackmacgap"), .comms)
        XCTAssertEqual(StageCategory.classify("com.apple.mail"), .comms)
        XCTAssertEqual(StageCategory.classify("com.google.Chrome"), .browse)
        XCTAssertEqual(StageCategory.classify("company.thebrowser.Browser"), .browse)
        XCTAssertEqual(StageCategory.classify("com.apple.dt.Xcode"), .work)
    }

    func testSortPlanReusesMatchingStagesAndCreatesMissingOnes() {
        let plan = SortPlan.make(bundleIDs: ["com.apple.Safari", "com.apple.dt.Xcode", "com.apple.MobileSMS"], stageNames: ["work", "Personal"], stageLimit: 9)
        XCTAssertEqual(plan.create, ["Comms", "Browse"])
        XCTAssertEqual(plan.assignments, ["Browse", "work", "Comms"])  // existing "work" reused, case-insensitive
    }

    func testSortPlanFallsBackToFirstStageAtTheLimit() {
        let names = (1...9).map { "S\($0)" }
        let plan = SortPlan.make(bundleIDs: ["com.apple.Safari"], stageNames: names, stageLimit: 9)
        XCTAssertTrue(plan.create.isEmpty)
        XCTAssertEqual(plan.assignments, ["S1"])
    }

    func testScrollAccumulatorFiresOncePerGesture() {
        var scroll = ScrollAccumulator(threshold: 20, cooldown: 0.4)
        XCTAssertEqual(scroll.add(delta: -8, at: 0.00), 0)
        XCTAssertEqual(scroll.add(delta: -8, at: 0.02), 0)
        XCTAssertEqual(scroll.add(delta: -8, at: 0.04), 1)   // crossed threshold downward: next Stage
        XCTAssertEqual(scroll.add(delta: -30, at: 0.10), 0)  // momentum inside cooldown
        XCTAssertEqual(scroll.add(delta: 25, at: 0.60), -1)  // new gesture upward: previous Stage
    }

    func testScrollAccumulatorResetsWhenDirectionChanges() {
        var scroll = ScrollAccumulator(threshold: 20, cooldown: 0.4)
        XCTAssertEqual(scroll.add(delta: -15, at: 0), 0)
        XCTAssertEqual(scroll.add(delta: 10, at: 0.05), 0)   // reversal discards the partial downward gesture
        XCTAssertEqual(scroll.add(delta: 10, at: 0.10), -1)
    }
}

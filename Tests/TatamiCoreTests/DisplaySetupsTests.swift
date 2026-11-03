import XCTest
@testable import TatamiCore

/// Display setups: one remembered layout per combination of connected displays, so home, work and laptop-alone never mix.
final class DisplaySetupsTests: XCTestCase {
    private let home = ["builtin", "portable", "room"]
    private let work = ["builtin", "portable", "office"]
    private let stage = UUID()

    private func checkpoint(windows: Int = 2) -> Checkpoint {
        let list = (0..<windows).map { index in
            CheckpointWindow(windowNumber: UInt32(index), pid: 100, bundleID: "app.\(index)", title: "t\(index)",
                             frame: Rect(CGRect(x: 0, y: 0, width: 100, height: 100)), stageID: stage, displayKey: "builtin")
        }
        return Checkpoint(activeStageID: stage, lastFocused: [:], windows: list)
    }

    // MARK: identity

    func testASetupIsTheWholeSetOfDisplaysInAnyOrder() {
        XCTAssertEqual(DisplaySetupKey.make(["b", "a", "c"]), DisplaySetupKey.make(["c", "b", "a"]))
        XCTAssertEqual(DisplaySetupKey.make(["a", "a", "b"]), DisplaySetupKey.make(["b", "a"]), "a repeated key counts once")
    }

    func testTwoPlacesSharingAMonitorAreDifferentSetups() {
        XCTAssertNotEqual(DisplaySetupKey.make(home), DisplaySetupKey.make(work))
    }

    func testNoDisplaysIsNoSetup() {
        XCTAssertNil(DisplaySetupKey.make([]))
    }

    // MARK: the store

    func testASavedSetupIsFoundOnlyByTheExactSameDisplays() {
        var store = DisplaySetupStore()
        XCTAssertTrue(store.save(checkpoint(), displayKeys: home, displayNames: ["Laptop", "Portable", "Room"], at: Date(timeIntervalSince1970: 1)))
        XCTAssertNotNil(store.setup(for: home.reversed()))
        XCTAssertNil(store.setup(for: work), "same portable monitor, different place")
        XCTAssertNil(store.setup(for: ["builtin", "portable"]), "a subset is a different setup")
        XCTAssertNil(store.setup(for: home + ["extra"]), "a superset is a different setup")
    }

    func testSavingAgainReplacesTheLayoutAndKeepsYourName() {
        var store = DisplaySetupStore()
        _ = store.save(checkpoint(windows: 2), displayKeys: home, displayNames: [], at: Date(timeIntervalSince1970: 1))
        let key = DisplaySetupKey.make(home)!
        XCTAssertTrue(store.rename(key, to: "Home"))
        _ = store.save(checkpoint(windows: 5), displayKeys: home, displayNames: [], at: Date(timeIntervalSince1970: 9))
        XCTAssertEqual(store.setups.count, 1)
        XCTAssertEqual(store.setup(for: home)?.checkpoint.windows.count, 5)
        XCTAssertEqual(store.setup(for: home)?.title, "Home")
        XCTAssertEqual(store.setup(for: home)?.lastUsed, Date(timeIntervalSince1970: 9))
    }

    func testAnEmptyOrAbsurdCheckpointNeverReplacesAGoodOne() {
        var store = DisplaySetupStore()
        _ = store.save(checkpoint(windows: 3), displayKeys: home, displayNames: [], at: Date())
        XCTAssertFalse(store.save(checkpoint(windows: 0), displayKeys: home, displayNames: [], at: Date()), "an empty scan")
        XCTAssertFalse(store.save(checkpoint(windows: 501), displayKeys: home, displayNames: [], at: Date()), "too many windows")
        XCTAssertFalse(store.save(checkpoint(), displayKeys: [], displayNames: [], at: Date()), "no displays")
        XCTAssertEqual(store.setup(for: home)?.checkpoint.windows.count, 3)
    }

    func testTheEightMostRecentSetupsAreKept() {
        var store = DisplaySetupStore()
        for index in 0..<10 { _ = store.save(checkpoint(), displayKeys: ["d\(index)"], displayNames: [], at: Date(timeIntervalSince1970: Double(index))) }
        XCTAssertEqual(store.setups.count, DisplaySetupStore.maxSetups)
        XCTAssertNil(store.setup(for: ["d0"]))
        XCTAssertNil(store.setup(for: ["d1"]))
        XCTAssertNotNil(store.setup(for: ["d9"]))
    }

    func testUsingASetupKeepsItFromBeingEvicted() {
        var store = DisplaySetupStore()
        for index in 0..<8 { _ = store.save(checkpoint(), displayKeys: ["d\(index)"], displayNames: [], at: Date(timeIntervalSince1970: Double(index))) }
        store.touch(DisplaySetupKey.make(["d0"])!, at: Date(timeIntervalSince1970: 100))
        _ = store.save(checkpoint(), displayKeys: ["new"], displayNames: [], at: Date(timeIntervalSince1970: 101))
        XCTAssertNotNil(store.setup(for: ["d0"]), "recently used")
        XCTAssertNil(store.setup(for: ["d1"]), "the least recently used went")
    }

    func testNamesAreTrimmedLimitedAndCanBeCleared() {
        var store = DisplaySetupStore()
        _ = store.save(checkpoint(), displayKeys: home, displayNames: ["Laptop", "Portable", "Room"], at: Date())
        let key = DisplaySetupKey.make(home)!
        XCTAssertEqual(store.setup(for: home)?.title, "Laptop + Portable + Room", "named after its displays until you rename it")
        XCTAssertTrue(store.rename(key, to: "  Home  "))
        XCTAssertEqual(store.setup(for: home)?.title, "Home")
        XCTAssertFalse(store.rename(key, to: String(repeating: "x", count: 61)))
        XCTAssertTrue(store.rename(key, to: "   "), "an empty name goes back to the automatic one")
        XCTAssertEqual(store.setup(for: home)?.title, "Laptop + Portable + Room")
        XCTAssertFalse(store.rename("no such setup", to: "X"))
    }

    func testASetupCanBeForgotten() {
        var store = DisplaySetupStore()
        _ = store.save(checkpoint(), displayKeys: home, displayNames: [], at: Date())
        store.remove(DisplaySetupKey.make(home)!)
        XCTAssertNil(store.setup(for: home))
    }

    func testTheStoreSurvivesASaveAndLoadAndTrimsAnOversizedFile() throws {
        var store = DisplaySetupStore()
        _ = store.save(checkpoint(), displayKeys: home, displayNames: ["A"], at: Date(timeIntervalSince1970: 5))
        let loaded = try JSONDecoder().decode(DisplaySetupStore.self, from: JSONEncoder().encode(store))
        XCTAssertNotNil(loaded.setup(for: home))
        // a hand-edited file with too many setups
        var big = DisplaySetupStore()
        for index in 0..<8 { _ = big.save(checkpoint(), displayKeys: ["d\(index)"], displayNames: [], at: Date(timeIntervalSince1970: Double(index))) }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(big)) as! [String: Any]
        var setups = object["setups"] as! [[String: Any]]
        setups += setups.map { var copy = $0; copy["key"] = "x" + ($0["key"] as! String); return copy }
        object["setups"] = setups
        let trimmed = try JSONDecoder().decode(DisplaySetupStore.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertLessThanOrEqual(trimmed.setups.count, DisplaySetupStore.maxSetups)
    }

    // MARK: what to do when displays change

    func testAKnownSetupFollowsThePolicyAnUnknownOneIsOnlyTracked() {
        XCTAssertEqual(DisplaySetupRules.action(policy: .restore, known: true), .restore)
        XCTAssertEqual(DisplaySetupRules.action(policy: .ask, known: true), .ask)
        XCTAssertEqual(DisplaySetupRules.action(policy: .nothing, known: true), .track)
        for policy in DisplayChangePolicy.allCases {
            XCTAssertEqual(DisplaySetupRules.action(policy: policy, known: false), .track, "never apply another setup's layout")
        }
    }

    // MARK: eviction and loading, hardened

    func testTheSetupJustSavedIsNeverTheOneEvictedEvenOnATie() {
        var store = DisplaySetupStore()
        let same = Date(timeIntervalSince1970: 50)
        for index in 0..<8 { _ = store.save(checkpoint(), displayKeys: ["d\(index)"], displayNames: [], at: same) }
        XCTAssertTrue(store.save(checkpoint(), displayKeys: ["new"], displayNames: [], at: same))
        XCTAssertNotNil(store.setup(for: ["new"]), "saved means kept")
        XCTAssertEqual(store.setups.count, DisplaySetupStore.maxSetups)
    }

    func testTheSetupJustSavedSurvivesAClockThatWentBackwards() {
        var store = DisplaySetupStore()
        for index in 0..<8 { _ = store.save(checkpoint(), displayKeys: ["d\(index)"], displayNames: [], at: Date(timeIntervalSince1970: 1000 + Double(index))) }
        XCTAssertTrue(store.save(checkpoint(), displayKeys: ["new"], displayNames: [], at: Date(timeIntervalSince1970: 1)))
        XCTAssertNotNil(store.setup(for: ["new"]))
    }

    func testBoundariesAreAccepted() {
        var store = DisplaySetupStore()
        XCTAssertTrue(store.save(checkpoint(windows: 500), displayKeys: home, displayNames: [], at: Date()))
        XCTAssertTrue(store.rename(DisplaySetupKey.make(home)!, to: String(repeating: "x", count: 60)))
    }

    func testWindowTitlesAreCappedWhenSaved() {
        var store = DisplaySetupStore()
        var cp = checkpoint(windows: 1)
        cp.windows[0].title = String(repeating: "t", count: 5000)
        _ = store.save(cp, displayKeys: home, displayNames: [], at: Date())
        XCTAssertLessThanOrEqual(store.setup(for: home)?.checkpoint.windows[0].title.count ?? 0, 200)
    }

    func testOldSetupsCanBePruned() {
        var store = DisplaySetupStore()
        _ = store.save(checkpoint(), displayKeys: ["old"], displayNames: [], at: Date(timeIntervalSince1970: 0))
        _ = store.save(checkpoint(), displayKeys: ["fresh"], displayNames: [], at: Date(timeIntervalSince1970: 90 * 86_400))
        store.prune(olderThan: 60 * 86_400, now: Date(timeIntervalSince1970: 100 * 86_400))
        XCTAssertNil(store.setup(for: ["old"]))
        XCTAssertNotNil(store.setup(for: ["fresh"]))
    }

    func testARoundTripKeepsEverything() throws {
        var store = DisplaySetupStore()
        var cp = checkpoint(windows: 3)
        cp.lastFocused = [stage: 7]
        cp.layouts = [SavedLayout(stageID: stage, displayKey: "builtin", layout: PaneLayout(root: .pane(Pane())))]
        _ = store.save(cp, displayKeys: home, displayNames: ["Laptop"], at: Date(timeIntervalSince1970: 123))
        _ = store.rename(DisplaySetupKey.make(home)!, to: "Home")
        let loaded = try JSONDecoder().decode(DisplaySetupStore.self, from: JSONEncoder().encode(store)).setup(for: home)
        XCTAssertEqual(loaded?.title, "Home")
        XCTAssertEqual(loaded?.lastUsed, Date(timeIntervalSince1970: 123))
        XCTAssertEqual(loaded?.checkpoint.windows.count, 3)
        XCTAssertEqual(loaded?.checkpoint.lastFocused[stage], 7)
        XCTAssertEqual(loaded?.checkpoint.layouts?.count, 1)
    }

    func testOneCorruptSetupDoesNotCostYouTheOthers() throws {
        var store = DisplaySetupStore()
        _ = store.save(checkpoint(), displayKeys: home, displayNames: [], at: Date())
        _ = store.save(checkpoint(), displayKeys: work, displayNames: [], at: Date())
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store)) as! [String: Any]
        var setups = object["setups"] as! [[String: Any]]
        setups.append(["key": "broken"])  // missing every other field
        object["setups"] = setups
        let loaded = try JSONDecoder().decode(DisplaySetupStore.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(loaded.setups.count, 2)
    }

    func testALoadedFileWithoutSetupsIsEmpty() throws {
        XCTAssertTrue(try JSONDecoder().decode(DisplaySetupStore.self, from: Data("{}".utf8)).setups.isEmpty)
    }

    func testLoadingDropsDuplicatesAndOversizedSetupsAndKeepsTheNewest() throws {
        var store = DisplaySetupStore()
        _ = store.save(checkpoint(windows: 1), displayKeys: home, displayNames: [], at: Date(timeIntervalSince1970: 10))
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store)) as! [String: Any]
        var setups = object["setups"] as! [[String: Any]]
        var older = setups[0]; older["lastUsed"] = -2_000_000_000.0  // Dates encode relative to 2001: this is 1937
        setups.append(older)  // same key, older
        object["setups"] = setups
        let loaded = try JSONDecoder().decode(DisplaySetupStore.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(loaded.setups.count, 1, "one setup per key")
        XCTAssertEqual(loaded.setups[0].lastUsed, Date(timeIntervalSince1970: 10), "the newest wins")

        var huge = DisplaySetupStore()
        _ = huge.save(checkpoint(windows: 500), displayKeys: work, displayNames: [], at: Date())
        var hugeObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(huge)) as! [String: Any]
        var hugeSetups = hugeObject["setups"] as! [[String: Any]]
        var checkpointObject = hugeSetups[0]["checkpoint"] as! [String: Any]
        let windows = checkpointObject["windows"] as! [[String: Any]]
        checkpointObject["windows"] = windows + windows  // 1000 windows
        hugeSetups[0]["checkpoint"] = checkpointObject
        hugeObject["setups"] = hugeSetups
        let dropped = try JSONDecoder().decode(DisplaySetupStore.self, from: JSONSerialization.data(withJSONObject: hugeObject))
        XCTAssertTrue(dropped.setups.isEmpty, "a file with more windows than we ever save is not trusted")
    }
}

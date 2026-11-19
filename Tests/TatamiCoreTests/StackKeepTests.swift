import XCTest
@testable import TatamiCore

/// Issue #24: a window stacked as a tab must come back to its stack, not get a tile of its own.
///
/// `AppModel.syncLayouts` drops a window from its layout as soon as it is no longer a layout candidate (the user
/// minimized it, or it floated for a moment) and, when it is a candidate again, treats it as a new window and runs
/// `PaneLayout.place` with the Room's placement policy. With `.automatic` (the default) and fewer than four panes that
/// splits the focused pane, so the stacked tab leaves its stack. These tests replay that sync cycle on `PaneLayout`.
final class StackKeepTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    private let area = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    /// Pane 1 stacks a, b, c; pane 2 holds d.
    private func layout() -> (PaneLayout, stack: UUID, other: UUID) {
        var layout = PaneLayout(root: .pane(Pane()))
        let stack = layout.root.paneIDs[0]
        for window in [a, b, c] { layout.add(window, to: stack) }
        let other = layout.split(stack, axis: .horizontal, moving: d)!
        return (layout, stack, other)
    }

    /// What one sync pass does to a window that left the layout and came back (minimize, then restore from the Dock).
    private func leaveAndReturn(_ window: WindowID, in layout: inout PaneLayout, policy: NewWindowPlacement) {
        layout.remove(window, keepEmptyPanes: false)  // syncLayouts: no longer a layout candidate
        layout.place(window, policy: policy, in: area)  // syncLayouts: a candidate again, so "new"
    }

    func testAMinimizedTabRestoredFromTheDockRejoinsItsStack() {
        var (l, stack, _) = layout()
        leaveAndReturn(b, in: &l, policy: .automatic)
        XCTAssertEqual(l.root.panes.count, 2, "the restored tab got a tile of its own")
        XCTAssertEqual(l.pane(containing: b)?.id, stack)
        XCTAssertEqual(Set(l.root.pane(stack)?.tabs ?? []), [a, b, c])
    }

    func testAStackSurvivesEveryTabLeavingAndReturningInTurn() {
        var (l, stack, _) = layout()
        l.focused = stack
        for window in [a, b, c] { leaveAndReturn(window, in: &l, policy: .automatic) }
        XCTAssertEqual(l.root.panes.count, 2)
        XCTAssertEqual(Set(l.root.pane(stack)?.tabs ?? []), [a, b, c])
    }

    func testEveryPlacementPolicyReturnsAStackedTabToItsStack() {
        for policy in NewWindowPlacement.allCases {
            var (l, stack, _) = layout()
            leaveAndReturn(c, in: &l, policy: policy)
            XCTAssertEqual(l.pane(containing: c)?.id, stack, "policy \(policy) moved the returning tab out of its stack")
        }
    }

    // MARK: what must not change

    func testAReturningWindowWhosePaneIsGoneIsPlacedByPolicy() {
        var (l, _, other) = layout()
        leaveAndReturn(d, in: &l, policy: .automatic)  // d was alone: its pane closed, so it gets a tile of its own again
        XCTAssertEqual(l.root.panes.count, 2)
        XCTAssertNil(l.root.pane(other))
        XCTAssertEqual(l.pane(containing: d)?.tabs, [d])
    }

    func testANewWindowStillFollowsThePlacementPolicy() {
        var (l, _, _) = layout()
        l.place(UUID(), policy: .automatic, in: area)
        XCTAssertEqual(l.root.panes.count, 3)
    }

    func testADeliberateSplitStillSplitsTheStack() {
        var (l, stack, _) = layout()
        let fresh = l.split(stack, axis: .vertical, moving: b)
        XCTAssertEqual(l.pane(containing: b)?.id, fresh)
        XCTAssertEqual(l.root.panes.count, 3)
    }

    func testTheSavedLayoutFormatIsUnchanged() throws {
        var (l, _, _) = layout()
        l.remove(b, keepEmptyPanes: false)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(l)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["root", "focused"])  // zoomed is nil, so it is left out
        XCTAssertTrue(try JSONDecoder().decode(PaneLayout.self, from: JSONEncoder().encode(l)).returnPanes.isEmpty)
    }
}

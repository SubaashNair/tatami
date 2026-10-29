import Foundation
import CoreGraphics

// Tiles layout engine (M3). Pure value types: every mutation is a cheap copy, which also makes undo trivial.
// Frames use AX coordinates (y grows downward).

public typealias WindowID = UUID

public enum Axis: String, Codable { case horizontal, vertical }  // horizontal: children left to right
public enum Direction: String, Codable { case left, right, up, down }

public enum NewWindowPlacement: String, Codable, CaseIterable {
    case automatic, active, adjacentRight, adjacentBelow, own
}

/// One tile. `tabs` in bar order; `mru` most recent first, for picking the next tab when one leaves (TIL-03).
public struct Pane: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var tabs: [WindowID] = []
    public var selected: WindowID?
    public var mru: [WindowID] = []
    public init(tabs: [WindowID] = []) { self.tabs = tabs; selected = tabs.first; mru = tabs }

    mutating func add(_ window: WindowID) {
        if !tabs.contains(window) { tabs.append(window) }
        select(window)
    }
    mutating func select(_ window: WindowID) {
        guard tabs.contains(window) else { return }
        selected = window
        mru.removeAll { $0 == window }; mru.insert(window, at: 0)
    }
    mutating func remove(_ window: WindowID) {
        tabs.removeAll { $0 == window }; mru.removeAll { $0 == window }
        if selected == window { selected = mru.first ?? tabs.first }
    }
}

public struct Child: Codable, Equatable {
    public var node: LayoutNode
    public var weight: Double
}

/// n-ary tree (M3 decision 3): a split is a row or column of weighted children.
public indirect enum LayoutNode: Codable, Equatable {
    case pane(Pane)
    case split(Axis, [Child])

    public var panes: [Pane] {
        switch self {
        case .pane(let pane): [pane]
        case .split(_, let children): children.flatMap(\.node.panes)
        }
    }
    public var paneIDs: [UUID] { panes.map(\.id) }
    public func pane(_ id: UUID) -> Pane? { panes.first { $0.id == id } }

    /// Transforms every pane; returning nil removes it. The result is not yet normalized.
    func mapPanes(_ transform: (Pane) -> Pane?) -> LayoutNode? {
        switch self {
        case .pane(let pane): return transform(pane).map(LayoutNode.pane)
        case .split(let axis, let children):
            let mapped = children.compactMap { child in child.node.mapPanes(transform).map { Child(node: $0, weight: child.weight) } }
            return mapped.isEmpty ? nil : .split(axis, mapped)
        }
    }

    /// Replaces the pane `id` with an arbitrary subtree.
    func replacing(_ id: UUID, with replacement: LayoutNode) -> LayoutNode {
        switch self {
        case .pane(let pane): return pane.id == id ? replacement : self
        case .split(let axis, let children):
            return .split(axis, children.map { Child(node: $0.node.replacing(id, with: replacement), weight: $0.weight) })
        }
    }

    /// No empty or single-child splits; a child split on the parent's axis is flattened into it, keeping its share.
    func normalized() -> LayoutNode? {
        switch self {
        case .pane: return self
        case .split(let axis, let children):
            var flat: [Child] = []
            for child in children {
                guard let node = child.node.normalized() else { continue }
                if case .split(let inner, let grandchildren) = node, inner == axis {
                    let total = grandchildren.map(\.weight).reduce(0, +)
                    flat += grandchildren.map { Child(node: $0.node, weight: $0.weight * child.weight / total) }
                } else {
                    flat.append(Child(node: node, weight: child.weight))
                }
            }
            if flat.isEmpty { return nil }
            return flat.count == 1 ? flat[0].node : .split(axis, flat)
        }
    }

    /// Child indices from the root down to the pane `id`.
    func path(to id: UUID) -> [Int]? {
        switch self {
        case .pane(let pane): return pane.id == id ? [] : nil
        case .split(_, let children):
            for (index, child) in children.enumerated() {
                if let rest = child.node.path(to: id) { return [index] + rest }
            }
            return nil
        }
    }

    func node(at path: ArraySlice<Int>) -> LayoutNode {
        guard let first = path.first, case .split(_, let children) = self else { return self }
        return children[first].node.node(at: path.dropFirst())
    }

    func replacingNode(at path: ArraySlice<Int>, with node: LayoutNode) -> LayoutNode {
        guard let first = path.first, case .split(let axis, var children) = self else { return node }
        children[first].node = children[first].node.replacingNode(at: path.dropFirst(), with: node)
        return .split(axis, children)
    }

    func evened() -> LayoutNode {
        switch self {
        case .pane: return self
        case .split(let axis, let children): return .split(axis, children.map { Child(node: $0.node.evened(), weight: 1) })
        }
    }

    static func divide(_ rect: CGRect, _ axis: Axis, _ children: [Child]) -> [CGRect] {
        let total = children.map(\.weight).reduce(0, +)
        var offset = 0.0
        return children.map { child in
            let share = child.weight / total
            defer { offset += share }
            return axis == .horizontal
                ? CGRect(x: rect.minX + rect.width * offset, y: rect.minY, width: rect.width * share, height: rect.height)
                : CGRect(x: rect.minX, y: rect.minY + rect.height * offset, width: rect.width, height: rect.height * share)
        }
    }

    func rects(in rect: CGRect) -> [UUID: CGRect] {
        switch self {
        case .pane(let pane): return [pane.id: rect]
        case .split(let axis, let children):
            return zip(children, Self.divide(rect, axis, children)).reduce(into: [:]) { $0.merge($1.0.node.rects(in: $1.1)) { a, _ in a } }
        }
    }

    /// The rect of the node at `path`, starting from `rect` for the root.
    func rect(at path: ArraySlice<Int>, in rect: CGRect) -> CGRect {
        guard let first = path.first, case .split(let axis, let children) = self else { return rect }
        return children[first].node.rect(at: path.dropFirst(), in: Self.divide(rect, axis, children)[first])
    }
}

public struct PaneFrame: Equatable {
    public var pane: CGRect
    /// The pane minus its tab bar: where the selected window goes.
    public var window: CGRect
}

public struct PaneLayout: Codable, Equatable {
    public var root: LayoutNode
    public var focused: UUID
    public var zoomed: UUID?
    static let maxAutoPanes = 4
    static let minShare = 0.05

    public init(root: LayoutNode, focused: UUID? = nil) {
        self.root = root
        self.focused = focused ?? root.paneIDs[0]
    }

    public var windows: [WindowID] { root.panes.flatMap(\.tabs) }
    public func pane(containing window: WindowID) -> Pane? { root.panes.first { $0.tabs.contains(window) } }

    // MARK: building

    /// Rows of pane counts for `n` panes: a single row on wide displays, otherwise a near-square grid.
    static func gridRows(_ n: Int, aspect: Double) -> [Int] {
        switch n {
        case ...1: return [1]
        case 2: return aspect >= 1 ? [2] : [1, 1]
        case 3: return aspect >= 2.5 ? [3] : [2, 1]
        default:
            let columns = Int(ceil(sqrt(Double(n))))
            return stride(from: 0, to: n, by: columns).map { min(columns, n - $0) }
        }
    }

    static func grid(_ panes: [Pane], aspect: Double) -> LayoutNode {
        var remaining = panes[...]
        let rows: [LayoutNode] = gridRows(panes.count, aspect: aspect).map { count in
            let row = remaining.prefix(count).map { Child(node: .pane($0), weight: 1) }
            remaining = remaining.dropFirst(count)
            return row.count == 1 ? row[0].node : .split(.horizontal, row)
        }
        return rows.count == 1 ? rows[0] : .split(.vertical, rows.map { Child(node: $0, weight: 1) })
    }

    /// Entering Tiles (M3 decision 4): one pane per window up to four; extras join the largest pane as tabs.
    public static func balanced(windows: [WindowID], aspect: Double) -> PaneLayout {
        guard !windows.isEmpty else { return PaneLayout(root: .pane(Pane())) }
        let own = windows.prefix(maxAutoPanes).map { Pane(tabs: [$0]) }
        var layout = PaneLayout(root: grid(own, aspect: aspect))
        let unit = CGRect(x: 0, y: 0, width: aspect, height: 1)
        let rects = layout.root.rects(in: unit)
        if let largest = own.map(\.id).max(by: { (rects[$0]?.width ?? 0) * (rects[$0]?.height ?? 0) < (rects[$1]?.width ?? 0) * (rects[$1]?.height ?? 0) }) {
            for window in windows.dropFirst(maxAutoPanes) { layout.add(window, to: largest) }
        }
        layout.focused = own[0].id
        return layout
    }

    // MARK: tabs and membership

    private mutating func updatePane(_ id: UUID, _ change: (inout Pane) -> Void) {
        root = root.mapPanes { pane in
            guard pane.id == id else { return pane }
            var copy = pane; change(&copy); return copy
        } ?? root
    }

    public mutating func add(_ window: WindowID, to pane: UUID) {
        if let current = self.pane(containing: window), current.id != pane { remove(window, keepEmptyPanes: true) }
        updatePane(pane) { $0.add(window) }
        focused = pane
    }

    public mutating func select(_ window: WindowID) {
        guard let pane = pane(containing: window) else { return }
        updatePane(pane.id) { $0.select(window) }
        focused = pane.id
    }

    public mutating func cycleTab(_ offset: Int) {
        guard let pane = root.pane(focused), let selected = pane.selected, let index = pane.tabs.firstIndex(of: selected), pane.tabs.count > 1 else { return }
        let count = pane.tabs.count
        select(pane.tabs[((index + offset) % count + count) % count])
    }

    /// Removes a window; an emptied pane goes too unless kept (M3 decision 10). At least one pane always remains.
    public mutating func remove(_ window: WindowID, keepEmptyPanes: Bool) {
        guard let pane = pane(containing: window) else { return }
        updatePane(pane.id) { $0.remove(window) }
        if !keepEmptyPanes, root.pane(pane.id)?.tabs.isEmpty == true, root.panes.count > 1 { removePane(pane.id) }
        // A zoomed pane that emptied would leave the display blank: every other pane is hidden behind it.
        if let zoomed, root.pane(zoomed)?.tabs.isEmpty != false { self.zoomed = nil }
    }

    /// Removes a pane; its windows move to the focused (or first remaining) pane.
    public mutating func removePane(_ id: UUID) {
        guard let pane = root.pane(id), root.panes.count > 1 else { return }
        root = (root.mapPanes { $0.id == id ? nil : $0 }?.normalized()) ?? .pane(Pane())
        if zoomed == id { zoomed = nil }
        if root.pane(focused) == nil { focused = root.paneIDs[0] }
        for window in pane.tabs { updatePane(focused) { $0.add(window) } }
    }

    public mutating func move(_ window: WindowID, to target: UUID, keepEmptyPanes: Bool) {
        guard root.pane(target) != nil, pane(containing: window)?.id != target else { return }
        remove(window, keepEmptyPanes: keepEmptyPanes)
        if root.pane(target) != nil { add(window, to: target) }
    }

    public mutating func swap(_ first: UUID, _ second: UUID) {
        guard let a = root.pane(first), let b = root.pane(second), first != second else { return }
        root = root.mapPanes { pane in
            var copy = pane == a ? b : pane == b ? a : pane
            copy.id = pane.id
            return copy
        } ?? root
    }

    /// Splits `pane`, putting `window` (if any) in the new pane, which gets focus. Returns the new pane's id.
    @discardableResult public mutating func split(_ pane: UUID, axis: Axis, moving window: WindowID?) -> UUID? {
        guard let existing = root.pane(pane) else { return nil }
        if let window { remove(window, keepEmptyPanes: true) }
        let current = root.pane(pane) ?? existing
        let fresh = Pane(tabs: window.map { [$0] } ?? [])
        root = root.replacing(pane, with: .split(axis, [Child(node: .pane(current), weight: 1), Child(node: .pane(fresh), weight: 1)])).normalized() ?? root
        focused = fresh.id
        return fresh.id
    }

    public mutating func toggleZoom(_ pane: UUID) { zoomed = zoomed == pane ? nil : pane }

    // MARK: sizing

    public mutating func evenOut() { root = root.evened() }

    /// Reflow as Grid: same panes and contents, balanced grid arrangement.
    public mutating func reflow(aspect: Double) { root = Self.grid(root.panes, aspect: aspect) }

    /// Moves `amount` of share (weights) between the pane's branch and its neighbour at the deepest suitable split.
    private mutating func transfer(pane: UUID, axis: Axis?, towardNext: Bool?, amount: (Double, CGRect) -> Double, area: CGRect) {
        guard let path = root.path(to: pane) else { return }
        for depth in stride(from: path.count - 1, through: 0, by: -1) {
            let prefix = path.prefix(depth)
            guard case .split(let splitAxis, var children) = root.node(at: prefix[...]), axis == nil || axis == splitAxis else { continue }
            let index = path[depth]
            let candidates = towardNext.map { [$0 ? index + 1 : index - 1] } ?? [index + 1, index - 1]
            guard let neighbour = candidates.first(where: { children.indices.contains($0) }) else { continue }
            let total = children.map(\.weight).reduce(0, +)
            let rect = root.rect(at: prefix[...], in: area)
            let limit = total * Self.minShare
            var delta = amount(total, rect)
            delta = min(delta, children[neighbour].weight - limit)
            delta = max(delta, limit - children[index].weight)
            children[index].weight += delta
            children[neighbour].weight -= delta
            root = root.replacingNode(at: prefix[...], with: .split(splitAxis, children))
            return
        }
    }

    /// Keyboard grow/shrink: `fraction` of the enclosing split's space, taken from the next (or previous) sibling.
    public mutating func resize(_ pane: UUID, by fraction: Double) {
        transfer(pane: pane, axis: nil, towardNext: nil, amount: { total, _ in fraction * total }, area: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// The user dragged a managed window's edge (M3 decision 14): only the panes on either side of that edge change.
    public mutating func applyEdgeDrag(pane: UUID, expected: CGRect, actual: CGRect, in area: CGRect, gap: Double, tabBar: Double) {
        let edges: [(Double, Axis, Bool)] = [
            (actual.maxX - expected.maxX, .horizontal, true), (expected.minX - actual.minX, .horizontal, false),
            (actual.maxY - expected.maxY, .vertical, true), (expected.minY - actual.minY, .vertical, false),
        ]
        guard let (points, axis, next) = edges.max(by: { abs($0.0) < abs($1.0) }), abs(points) > 3 else { return }
        let inner = area.insetBy(dx: gap / 2, dy: gap / 2)
        transfer(pane: pane, axis: axis, towardNext: next, amount: { total, rect in
            points / (axis == .horizontal ? rect.width : rect.height) * total
        }, area: inner)
    }

    // MARK: geometry

    public func frames(in area: CGRect, gap: Double, tabBar: Double) -> [UUID: PaneFrame] {
        let inner = area.insetBy(dx: gap / 2, dy: gap / 2)
        let rects = zoomed.flatMap { root.pane($0) != nil ? [$0: inner] : nil } ?? root.rects(in: inner)
        return rects.mapValues { rect in
            let pane = rect.insetBy(dx: gap / 2, dy: gap / 2).integral
            return PaneFrame(pane: pane, window: CGRect(x: pane.minX, y: pane.minY + tabBar, width: pane.width, height: max(0, pane.height - tabBar)))
        }
    }

    /// The nearest candidate in `direction` that overlaps on the other axis. Works across displays when given every display's panes.
    public static func neighbour<ID: Equatable>(of frame: CGRect, toward direction: Direction, among candidates: [(ID, CGRect)]) -> ID? {
        let slack: CGFloat = 2
        func gap(_ other: CGRect) -> CGFloat? {
            switch direction {
            case .right: other.minX >= frame.maxX - slack ? other.minX - frame.maxX : nil
            case .left: other.maxX <= frame.minX + slack ? frame.minX - other.maxX : nil
            case .down: other.minY >= frame.maxY - slack ? other.minY - frame.maxY : nil
            case .up: other.maxY <= frame.minY + slack ? frame.minY - other.maxY : nil
            }
        }
        func overlap(_ other: CGRect) -> CGFloat {
            direction == .left || direction == .right
                ? min(frame.maxY, other.maxY) - max(frame.minY, other.minY)
                : min(frame.maxX, other.maxX) - max(frame.minX, other.minX)
        }
        return candidates.compactMap { id, rect -> (ID, CGFloat, CGFloat)? in
            guard let distance = gap(rect), overlap(rect) > 0 else { return nil }
            return (id, distance, overlap(rect))
        }.min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 > $1.2 }?.0
    }

    // MARK: persistence

    /// Rewrites window ids (e.g. after a relaunch); windows with no mapping are dropped, panes kept.
    public func remapped(_ map: [WindowID: WindowID]) -> PaneLayout {
        var copy = self
        copy.root = root.mapPanes { pane in
            var p = pane
            p.tabs = pane.tabs.compactMap { map[$0] }
            p.mru = pane.mru.compactMap { map[$0] }
            p.selected = pane.selected.flatMap { map[$0] } ?? p.mru.first ?? p.tabs.first
            return p
        } ?? root
        return copy
    }

    /// Removes empty panes (keeping at least one) and fixes focus.
    public func pruned() -> PaneLayout {
        var copy = self
        for pane in root.panes where pane.tabs.isEmpty { copy.removePane(pane.id) }
        return copy
    }

    // MARK: new windows

    /// M3 decision 9. Routing and Launch Here are decided by the caller before this runs.
    public mutating func place(_ window: WindowID, policy: NewWindowPlacement, in area: CGRect) {
        if root.panes.count == 1, root.panes[0].tabs.isEmpty { return add(window, to: root.paneIDs[0]) }
        let frames = self.frames(in: area, gap: 0, tabBar: 0)
        func own() {
            let rect = frames[focused]?.pane ?? area
            split(focused, axis: rect.width >= rect.height ? .horizontal : .vertical, moving: window)
        }
        func adjacent(_ direction: Direction, _ axis: Axis) {
            let others = frames.filter { $0.key != focused }.map { ($0.key, $0.value.pane) }
            if let rect = frames[focused]?.pane, let target = Self.neighbour(of: rect, toward: direction, among: others) { add(window, to: target) }
            else { split(focused, axis: axis, moving: window) }
        }
        switch policy {
        case .automatic: root.panes.count < Self.maxAutoPanes ? own() : add(window, to: focused)
        case .active: add(window, to: focused)
        case .own: own()
        case .adjacentRight: adjacent(.right, .horizontal)
        case .adjacentBelow: adjacent(.down, .vertical)
        }
    }
}

/// Layout undo (M3 decision 6): bounded, per display per Stage.
public struct LayoutHistory {
    private var stack: [PaneLayout] = []
    public let limit: Int
    public init(limit: Int = 20) { self.limit = limit }
    public var count: Int { stack.count }

    public mutating func record(_ layout: PaneLayout) {
        stack.append(layout)
        if stack.count > limit { stack.removeFirst(stack.count - limit) }
    }

    public mutating func undo() -> PaneLayout? { stack.popLast() }
}

import Foundation
import CoreGraphics

/// Keyboard navigation between windows by where they are on screen (freeform mode, and across displays).
public enum WindowFocus {
    /// The window to focus when moving `direction` from `frame`. A window directly beside the current one wins
    /// (nearest first, the one sharing more of the edge breaking ties). Otherwise the best window generally in that
    /// direction, so cascaded and overlapping windows still have a direction. Nil when nothing lies that way.
    public static func target<ID: Equatable>(from frame: CGRect, toward direction: Direction, among candidates: [(ID, CGRect)]) -> ID? {
        let beside = PaneLayout.neighbour(of: frame, toward: direction, among: candidates)
        let from = CGPoint(x: frame.midX, y: frame.midY)
        func score(_ rect: CGRect) -> CGFloat? {
            let dx = rect.midX - from.x, dy = rect.midY - from.y
            let (along, across): (CGFloat, CGFloat)
            switch direction {
            case .right: (along, across) = (dx, abs(dy))
            case .left: (along, across) = (-dx, abs(dy))
            case .down: (along, across) = (dy, abs(dx))
            case .up: (along, across) = (-dy, abs(dx))
            }
            // Sideways drift costs double, so a window straight ahead beats a nearer one off to the side.
            return along > 0 ? along + 2 * across : nil
        }
        let ahead = candidates.compactMap { id, rect in score(rect).map { (id: id, rect: rect, score: $0) } }.min { $0.score < $1.score }
        if let beside, let ahead, ahead.id != beside {
            // A window overlapping the current one is the natural next one, not a distant window that happens to sit beside it.
            let overlap = frame.intersection(ahead.rect)
            if !overlap.isNull, overlap.width > 0, overlap.height > 0 { return ahead.id }
        }
        return beside ?? ahead?.id
    }

    /// Top edges within this many points count as one row when ordering windows.
    static let rowTolerance: CGFloat = 24

    /// Windows in reading order: displays left to right, then top to bottom; within a display, top to bottom then left to right.
    public static func readingOrder<ID>(_ windows: [(id: ID, frame: CGRect)], displays: [CGRect]) -> [ID] {
        let ordered = displays.sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
        func displayIndex(_ frame: CGRect) -> Int {
            ordered.firstIndex { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) } ?? 0
        }
        let sorted = windows.sorted { (displayIndex($0.frame), $0.frame.minY, $0.frame.minX) < (displayIndex($1.frame), $1.frame.minY, $1.frame.minX) }
        // Side-by-side windows whose top edges differ by a few points belong to one row, so left stays before right.
        var rows: [[(id: ID, frame: CGRect)]] = []
        var rowDisplay = -1, rowTop: CGFloat = 0
        for window in sorted {
            let display = displayIndex(window.frame)
            if display == rowDisplay, window.frame.minY - rowTop <= rowTolerance {
                rows[rows.count - 1].append(window)
            } else {
                rows.append([window]); rowDisplay = display; rowTop = window.frame.minY
            }
        }
        return rows.flatMap { $0.sorted { $0.frame.minX < $1.frame.minX } }.map(\.id)
    }

    /// The window `offset` steps from `current` in `order`, wrapping. With no focused window it starts at an end.
    public static func cycle<ID: Equatable>(from current: ID?, offset: Int, in order: [ID]) -> ID? {
        guard !order.isEmpty else { return nil }
        guard let current, let index = order.firstIndex(of: current) else { return offset >= 0 ? order.first : order.last }
        guard order.count > 1 else { return nil }
        let count = order.count
        return order[((index + offset) % count + count) % count]
    }
}

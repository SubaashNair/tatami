import Foundation
import CoreGraphics

/// Pure logic for sending a window to another display.
public enum DisplayOrder {
    /// Display ids ordered left to right, then top to bottom, by each display's top-left corner.
    public static func ordered<ID>(_ displays: [(ID, CGRect)]) -> [ID] {
        displays.sorted { ($0.1.minX, $0.1.minY) < ($1.1.minX, $1.1.minY) }.map(\.0)
    }

    /// The display `offset` steps from `current` in arrangement order, wrapping around.
    /// Nil with fewer than two displays or when `current` is not among them.
    public static func neighbour<ID: Equatable>(of current: ID, offset: Int, in displays: [(ID, CGRect)]) -> ID? {
        let order = ordered(displays)
        guard order.count > 1, let index = order.firstIndex(of: current) else { return nil }
        let count = order.count
        return order[((index + offset) % count + count) % count]
    }
}

extension PaneLayout {
    /// Where a window arriving from another display joins this layout: the focused pane, else the first.
    public var landingPane: UUID { root.pane(focused)?.id ?? root.panes.first?.id ?? focused }
}

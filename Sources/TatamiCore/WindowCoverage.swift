import Foundation

/// Whether a window fills its display: the green maximize button, or an app that opened full size. Tatami treats that as the
/// pane zoom (the pane fills the display) rather than as a window that does not fit its pane, which would float it.
public enum WindowCoverage {
    /// Needed to count as filling the display. Tatami's own zoomed pane leaves room for the tab bar and a gap, so it stays under.
    static let fills = 0.99
    /// A zoomed window keeps counting until it is clearly smaller, so nothing flips back and forth.
    static let stays = 0.85

    private static func coverage(_ frame: CGRect, of area: CGRect) -> (width: Double, height: Double)? {
        guard area.width > 0, area.height > 0 else { return nil }
        let inside = frame.intersection(area)
        guard !inside.isNull else { return (0, 0) }
        return (Double(inside.width / area.width), Double(inside.height / area.height))
    }

    public static func fillsDisplay(_ frame: CGRect, area: CGRect) -> Bool {
        guard let c = coverage(frame, of: area) else { return false }
        return c.width >= fills && c.height >= fills
    }

    public static func stillFills(_ frame: CGRect, area: CGRect) -> Bool {
        guard let c = coverage(frame, of: area) else { return false }
        return c.width >= stays && c.height >= stays
    }
}

public enum MaximizeAction: Equatable { case zoom, unzoom, none }

/// What to do about a tiled window whose frame fills its display.
public enum MaximizeRules {
    /// - `zoomedByUs`: the pane was zoomed by this rule, not by you with the zoom key; only those are undone automatically.
    /// - `expected`: the frame Tatami last placed the window in; nil for a window it has not placed yet, which is placed
    ///   first and never judged on the size it opened with.
    /// - `justLeftFullScreen`: the frame is still moving back from full screen.
    public static func action(isZoomed: Bool, zoomedByUs: Bool, frame: CGRect, expected: CGRect?, area: CGRect, justLeftFullScreen: Bool) -> MaximizeAction {
        if justLeftFullScreen { return .none }
        if isZoomed { return zoomedByUs && !WindowCoverage.stillFills(frame, area: area) ? .unzoom : .none }
        guard let expected, !WindowCoverage.fillsDisplay(expected, area: area), WindowCoverage.fillsDisplay(frame, area: area) else { return .none }
        return .zoom
    }
}

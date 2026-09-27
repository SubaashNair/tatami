import Foundation
import CoreGraphics

// Pure geometry and identity logic for the window engine. All frames use AX coordinates
// (origin at the primary display's top-left, y grows downward).

/// Hardware identity of a monitor that survives port changes, replugging, and resolution changes.
public struct DisplayFingerprint: Codable, Equatable {
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var uuid: String
    public var frame: CGRect
    public init(vendor: UInt32, model: UInt32, serial: UInt32, uuid: String, frame: CGRect) {
        self.vendor = vendor; self.model = model; self.serial = serial; self.uuid = uuid; self.frame = frame
    }

    /// Stable keys, index-aligned with `displays`. Identical hardware (serial 0, twin monitors) is
    /// disambiguated by arrangement: left to right, then top to bottom.
    public static func keys(for displays: [DisplayFingerprint]) -> [String] {
        let bases = displays.map { d in d.vendor == 0 && d.model == 0 ? "uuid-\(d.uuid)" : "\(d.vendor)-\(d.model)-\(d.serial)" }
        var keys = bases
        for base in Set(bases) {
            let group = bases.indices.filter { bases[$0] == base }
            guard group.count > 1 else { continue }
            let ordered = group.sorted { (displays[$0].frame.minX, displays[$0].frame.minY) < (displays[$1].frame.minX, displays[$1].frame.minY) }
            for (ordinal, index) in ordered.enumerated() { keys[index] = "\(base)#\(ordinal)" }
        }
        return keys
    }
}

public enum ParkPlanner {
    /// macOS pulls back windows moved entirely off every screen, so a 1 pt corner stays on the display.
    public static let sliver: CGFloat = 1
    /// A window showing less than this share of its area is treated as parked.
    static let parkedVisibleShare: CGFloat = 0.02

    /// Bottom corners only: macOS clamps windows moved above the menu bar. Nil means every corner
    /// would overlap a neighbouring display, and the caller should minimize instead.
    public static func parkFrame(size: CGSize, display: CGRect, others: [CGRect]) -> CGRect? {
        let candidates = [
            CGPoint(x: display.maxX - sliver, y: display.maxY - sliver),                 // bottom-right
            CGPoint(x: display.minX - size.width + sliver, y: display.maxY - sliver),    // bottom-left
        ]
        return candidates.map { CGRect(origin: $0, size: size) }.first { frame in !others.contains { $0.intersects(frame) } }
    }

    public static func isParked(_ frame: CGRect, displays: [CGRect]) -> Bool {
        let area = frame.width * frame.height
        guard area > 0 else { return false }
        let visible = displays.reduce(0) { sum, display in
            let overlap = display.intersection(frame)
            return sum + (overlap.isNull ? 0 : overlap.width * overlap.height)
        }
        return visible < area * parkedVisibleShare
    }
}

public enum DisplayRemap {
    /// Keeps the window's relative position and size (a left-half window stays on the left half), clamped on-screen.
    public static func remap(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return Geometry.visibleFrame(frame, in: destination) }
        let sx = destination.width / source.width, sy = destination.height / source.height
        let scaled = CGRect(x: destination.minX + (frame.minX - source.minX) * sx, y: destination.minY + (frame.minY - source.minY) * sy,
                            width: frame.width * sx, height: frame.height * sy)
        return Geometry.visibleFrame(scaled, in: destination)
    }
}

/// A window as recorded in a checkpoint. `frame` is always the real (unparked) frame.
public struct CheckpointWindow: Codable, Equatable {
    public var windowNumber: UInt32?
    public var pid: Int32
    public var bundleID: String
    public var title: String
    public var frame: Rect
    public var stageID: UUID
    public var displayKey: String?
    /// The window's runtime id when saved, so saved pane layouts can be re-attached after a relaunch.
    public var id: UUID?
    public init(windowNumber: UInt32?, pid: Int32, bundleID: String, title: String, frame: Rect, stageID: UUID, displayKey: String?, id: UUID? = nil) {
        self.windowNumber = windowNumber; self.pid = pid; self.bundleID = bundleID; self.title = title
        self.frame = frame; self.stageID = stageID; self.displayKey = displayKey; self.id = id
    }

    /// saved index → live index. Window numbers are exact within one app process; after an app
    /// relaunch, fall back to app + title in order of appearance. Each live window matches once.
    public static func match(saved: [CheckpointWindow], live: [LiveWindowKey]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var taken = Set<Int>()
        for (s, window) in saved.enumerated() {
            guard let number = window.windowNumber,
                  let l = live.indices.first(where: { !taken.contains($0) && live[$0].pid == window.pid && live[$0].windowNumber == number }) else { continue }
            result[s] = l; taken.insert(l)
        }
        for (s, window) in saved.enumerated() where result[s] == nil {
            guard let l = live.indices.first(where: { !taken.contains($0) && live[$0].bundleID == window.bundleID && live[$0].title == window.title }) else { continue }
            result[s] = l; taken.insert(l)
        }
        return result
    }
}

public struct LiveWindowKey: Equatable {
    public var windowNumber: UInt32?
    public var pid: Int32
    public var bundleID: String
    public var title: String
    public init(windowNumber: UInt32?, pid: Int32, bundleID: String, title: String) {
        self.windowNumber = windowNumber; self.pid = pid; self.bundleID = bundleID; self.title = title
    }
}

public struct Checkpoint: Codable {
    public var version = 1
    public var date = Date()
    public var activeStageID: UUID
    /// Stage → window number of the last focused window on that Stage.
    public var lastFocused: [UUID: UInt32]
    public var windows: [CheckpointWindow]
    /// TabStack layouts (M3 decision 11). Optional so M1/M2 checkpoints still load.
    public var layouts: [SavedLayout]?
    public init(activeStageID: UUID, lastFocused: [UUID: UInt32], windows: [CheckpointWindow], layouts: [SavedLayout]? = nil) {
        self.activeStageID = activeStageID; self.lastFocused = lastFocused; self.windows = windows; self.layouts = layouts
    }
}

public struct SavedLayout: Codable {
    public var stageID: UUID
    public var displayKey: String
    public var layout: PaneLayout
    public init(stageID: UUID, displayKey: String, layout: PaneLayout) { self.stageID = stageID; self.displayKey = displayKey; self.layout = layout }
}

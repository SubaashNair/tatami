import AppKit

/// The Tatami mark for the menu bar: the app icon's frame and three panes in one colour, as a template image so macOS
/// tints it for light and dark menu bars. Geometry follows docs/icons/menubar-template.svg (a 36 unit square).
enum BrandMark {
    static func menuBarImage(points: CGFloat = 20) -> NSImage {
        let image = NSImage(size: NSSize(width: points, height: points), flipped: false) { _ in
            let unit = points / 36
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat) -> NSBezierPath {
                NSBezierPath(roundedRect: NSRect(x: x * unit, y: (36 - y - h) * unit, width: w * unit, height: h * unit), xRadius: radius * unit, yRadius: radius * unit)
            }
            NSColor.black.setStroke(); NSColor.black.setFill()
            let outline: [(NSBezierPath, CGFloat)] = [
                (rect(3, 6, 30, 24, radius: 5), 2.4),
                (rect(7.5, 10.5, 9.5, 6.5, radius: 2), 1.8),
                (rect(7.5, 19.5, 21, 6, radius: 2), 1.8),
            ]
            for (path, width) in outline { path.lineWidth = width * unit; path.stroke() }
            rect(19, 10.5, 9.5, 6.5, radius: 2).fill()  // the focused pane
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tatami"
        return image
    }
}

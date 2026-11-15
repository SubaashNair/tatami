import AppKit

/// Tatami's colours (docs/brand.md). Sage and Aotatami lead, Igusa acts, gold marks the focused pane.
enum Palette {
    static let sage = rgb(0x7FAE8F)
    static let aotatami = rgb(0xE2EAD7)
    static let igusa = rgb(0x3F6A52)
    static let paper = rgb(0xF5F5F0)
    static let shoji = rgb(0xEDF0E8)
    static let sumi = rgb(0x1E2B24)
    static let stone = rgb(0x5E665C)

    // Tab bars and the Room bar float over other apps and follow the system appearance, so their brand colours do too.
    /// The focused pane's outline: Amber on light (gold is too pale there), Focus Gold on dark.
    static let focus = dynamic(light: rgb(0x9A6F1E), dark: rgb(0xD9A441))
    /// The active Room in the Room bar.
    static let active = dynamic(light: igusa, dark: sage)
    /// The selected tab.
    static let selection = dynamic(light: aotatami, dark: NSColor.white.withAlphaComponent(0.14))

    private static func rgb(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
}

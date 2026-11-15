import Foundation

/// The colours a Room can give its tab bars.
public enum RoomTint: String, Codable, CaseIterable {
    case red, orange, yellow, green, teal, blue, purple, pink

    public var label: String { rawValue.capitalized }
}

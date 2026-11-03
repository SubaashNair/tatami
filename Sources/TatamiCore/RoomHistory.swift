import Foundation

/// "Previous Room": the Room each display (or the whole desk, with per-display Rooms off) showed before the current one.
/// Switching back records the switch like any other, so pressing the key again flips back.
public struct RoomHistory: Equatable {
    private var previous: [String: UUID] = [:]

    public init() {}

    private static func key(_ display: String?) -> String { display ?? "" }

    /// Notes a switch. Nothing is recorded when the Room did not change.
    public mutating func record(from old: UUID, to new: UUID, on display: String?) {
        guard old != new else { return }
        previous[Self.key(display)] = old
    }

    /// The Room to go back to: the one left last, if it still exists and is not the one showing.
    public func back(on display: String?, current: UUID, rooms: [UUID]) -> UUID? {
        guard let room = previous[Self.key(display)], room != current, rooms.contains(room) else { return nil }
        return room
    }

    /// Forgets a removed Room everywhere.
    public mutating func forget(_ room: UUID) { previous = previous.filter { $0.value != room } }
}

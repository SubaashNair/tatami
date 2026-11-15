import Foundation

/// The result of sending a Room to another display: `first` was showing on `firstDisplay` and now shows on `secondDisplay`,
/// and `second` the other way round.
public struct RoomSwap: Equatable {
    public var first: UUID
    public var second: UUID
    public var firstDisplay: String
    public var secondDisplay: String

    public init(first: UUID, second: UUID, firstDisplay: String, secondDisplay: String) {
        self.first = first; self.second = second; self.firstDisplay = firstDisplay; self.secondDisplay = secondDisplay
    }
}

extension WorkspaceState {
    /// Sends the Room showing on `a` to display `b`, and the Room that was on `b` to `a` (nothing is left without a Room).
    /// What belongs to a Room goes with it: its Tiles or Freeform choice, and its home display when that was the display
    /// it left. Nil, with nothing changed, when per-display Rooms is off, the displays are the same, or both show one Room.
    /// `displays` are all the connected displays, so the others keep the Room they show now.
    @discardableResult public mutating func swapRooms(between a: String, and b: String, displays: [String]) -> RoomSwap? {
        swapRooms(between: a, and: b, displays: DisplayDescriptor.keys(displays))
    }

    /// As above, with what is known about each display, so a home that came from the preference list moves with its Room too.
    @discardableResult public mutating func swapRooms(between a: String, and b: String, displays descriptors: [DisplayDescriptor]) -> RoomSwap? {
        let displays = descriptors.map(\.key)
        guard perDisplayRooms, a != b else { return nil }
        let first = activeRoomID(on: a), second = activeRoomID(on: b)
        guard first != second else { return nil }
        let firstTiled = isTiled(stage: first, display: a), secondTiled = isTiled(stage: second, display: b)
        let firstLivedHere = effectiveHome(of: first, displays: descriptors) == a, secondLivedHere = effectiveHome(of: second, displays: descriptors) == b

        for other in displays where other != a && other != b { displayRooms[other] = activeRoomID(on: other) }
        displayRooms[a] = second
        displayRooms[b] = first
        activeStageID = first
        setTiled(firstTiled, stage: first, display: b)
        setTiled(secondTiled, stage: second, display: a)
        // A Room that lived on the display it left now lives where it was sent: that choice comes first from now on.
        if firstLivedHere, let index = stages.firstIndex(where: { $0.id == first }) { stages[index].homeDisplay = b }
        if secondLivedHere, let index = stages.firstIndex(where: { $0.id == second }) { stages[index].homeDisplay = a }
        return RoomSwap(first: first, second: second, firstDisplay: a, secondDisplay: b)
    }
}

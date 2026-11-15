import CoreTransferable
import UniformTypeIdentifiers

/// What is dragged from a tab: the window's id, under a type only Tatami knows, so dropping it on a text field or in another
/// app does nothing and another app cannot make a drop look like a tab.
struct TabDrag: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tatamiTab)
    }
}

extension UTType {
    static let tatamiTab = UTType(exportedAs: "app.tatami.tab-drag")
}

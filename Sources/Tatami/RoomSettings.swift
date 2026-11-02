import SwiftUI
import TatamiCore

/// Per-Room settings: which display the Room lives on, and how its new windows open.
struct RoomSettingsSheet: View {
    @ObservedObject var model: AppModel
    let stageID: UUID
    let close: () -> Void

    private var stage: Stage? { model.state.stages.first { $0.id == stageID } }

    private static let layouts: [(placement: NewWindowPlacement?, label: String)] = [
        (nil, "Default (tabs when the Room lives on a display)"),
        (.active, "Tabs in the focused pane"),
        (.automatic, "Its own pane, then tabs after four panes"),
        (.own, "Always its own pane"),
        (.adjacentRight, "Next to the focused pane, on the right"),
        (.adjacentBelow, "Below the focused pane"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(stage?.name ?? "Room").font(.system(size: 24, weight: .medium, design: .serif))
            VStack(alignment: .leading, spacing: 6) {
                Picker("Lives on", selection: homeBinding) {
                    Text("Any display").tag(String?.none)
                    ForEach(model.displays) { display in Text(display.name).tag(String?.some(display.id)) }
                    if let home = stage?.homeDisplay, !model.displays.contains(where: { $0.id == home }) {
                        Text("An unplugged display").tag(String?.some(home))
                    }
                }
                Text("Apps routed to this Room (App Routing) open on that display. Choosing one turns on Each display shows its own Room.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Picker("New windows open as", selection: placementBinding) {
                    ForEach(Array(Self.layouts.enumerated()), id: \.offset) { _, option in Text(option.label).tag(option.placement) }
                }
                Text("With tabs, a second coding app joins the first one's pane instead of splitting the screen.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            HStack { Spacer(); Button("Done", action: close).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(32).frame(width: 480)
    }

    private var homeBinding: Binding<String?> {
        Binding(get: { stage?.homeDisplay }, set: { model.notice = model.assignHome($0, to: stageID) })
    }

    private var placementBinding: Binding<NewWindowPlacement?> {
        Binding(get: { stage?.placement }, set: { model.setRoomPlacement($0, for: stageID) })
    }
}

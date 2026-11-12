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
                Text("If that display is not connected, try").font(.system(size: 12, weight: .medium))
                ForEach(Array((stage?.homeFallbacks ?? []).enumerated()), id: \.offset) { index, choice in
                    HStack {
                        Text("\(index + 1). \(model.describe(choice))").font(.system(size: 12))
                        Spacer()
                        Button { removeChoice(at: index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("Remove this choice")
                    }
                }
                Menu("Add a choice") {
                    ForEach(model.displays) { display in Button(display.name) { addChoice(.key(display.id)) } }
                    Divider()
                    Button("The main display") { addChoice(.main) }
                    Button("The built-in display") { addChoice(.builtIn) }
                    Button("Any display that is not the main one") { addChoice(.secondary) }
                }.fixedSize()
                Text("The first choice that is connected wins, so the same setup works at home, at work and on the laptop alone. Importing from AeroSpace fills this in from its monitor lists.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Picker("New windows open as", selection: placementBinding) {
                    ForEach(Array(Self.layouts.enumerated()), id: \.offset) { _, option in Text(option.label).tag(option.placement) }
                }
                Text("With tabs, a second coding app joins the first one's pane instead of splitting the screen.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Tab bar colour").font(.system(size: 12, weight: .medium))
                HStack(spacing: 8) {
                    Button { model.setRoomTint(nil, for: stageID) } label: {
                        Image(systemName: stage?.tint == nil ? "circle.slash.fill" : "circle.slash").frame(width: 20, height: 20)
                    }.buttonStyle(.plain).help("No colour")
                    ForEach(RoomTint.allCases, id: \.self) { tint in
                        Button { model.setRoomTint(tint, for: stageID) } label: {
                            Circle().fill(tint.color).frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.primary.opacity(stage?.tint == tint ? 0.8 : 0), lineWidth: 2))
                        }.buttonStyle(.plain).help(tint.label)
                    }
                }
                Text("Tints this Room's tab bars so panes of different Rooms are told apart at a glance.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            HStack { Spacer(); Button("Done", action: close).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(32).frame(width: 480)
    }

    private func addChoice(_ choice: DisplayPreference) {
        let current = stage?.homeFallbacks ?? []
        if !current.contains(choice) { model.setRoomHomeChoices(current + [choice], for: stageID) }
    }

    private func removeChoice(at index: Int) {
        var current = stage?.homeFallbacks ?? []
        guard current.indices.contains(index) else { return }
        current.remove(at: index)
        model.setRoomHomeChoices(current, for: stageID)
    }

    private var homeBinding: Binding<String?> {
        Binding(get: { stage?.homeDisplay }, set: { model.notice = model.assignHome($0, to: stageID) })
    }

    private var placementBinding: Binding<NewWindowPlacement?> {
        Binding(get: { stage?.placement }, set: { model.setRoomPlacement($0, for: stageID) })
    }
}

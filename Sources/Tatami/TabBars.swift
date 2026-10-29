import AppKit
import SwiftUI
import TatamiCore

/// One thin panel above each pane on the active Stage (M3 decision 1). Frames follow layouts; content reads the
/// model live, so title changes show without re-tiling.
@MainActor final class TabBarController {
    private let model: AppModel
    private var panels: [UUID: NSPanel] = [:]  // pane id → panel

    init(model: AppModel) { self.model = model }

    func update() {
        guard model.managing else { panels.values.forEach { $0.orderOut(nil) }; return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var live = Set<UUID>()
        for (key, layout) in model.layouts where key.stage == model.state.activeStageID {
            guard let display = model.service.displays.first(where: { $0.id == key.display }) else { continue }
            let frames = layout.frames(in: display.area, gap: model.state.gap, tabBar: AppModel.tabBarHeight)
            for pane in layout.root.panes {
                guard let frame = frames[pane.id]?.pane else { continue }
                live.insert(pane.id)
                let panel = panels[pane.id] ?? makePanel(key: key, pane: pane.id)
                panels[pane.id] = panel
                // AX (top-left origin) → AppKit (bottom-left origin).
                panel.setFrame(NSRect(x: frame.minX, y: primaryHeight - frame.minY - AppModel.tabBarHeight, width: frame.width, height: AppModel.tabBarHeight), display: true)
                panel.orderFrontRegardless()
            }
        }
        for (id, panel) in panels where !live.contains(id) { panel.orderOut(nil); panels[id] = nil }
    }

    private func makePanel(key: LayoutKey, pane: UUID) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: TabBarView(model: model, key: key, paneID: pane))
        return panel
    }
}

struct TabBarView: View {
    @ObservedObject var model: AppModel
    let key: LayoutKey
    let paneID: UUID

    private var pane: Pane? { model.layouts[key]?.root.pane(paneID) }
    private var focusedPane: Bool { model.layouts[key]?.focused == paneID }

    var body: some View {
        HStack(spacing: 2) {
            if let pane, !pane.tabs.isEmpty {
                ForEach(pane.tabs, id: \.self) { id in
                    if let window = model.windows.first(where: { $0.id == id }) {
                        TabView(window: window, selected: pane.selected == id, tooSmall: model.minSizeWindows.contains(id))
                            .onTapGesture { model.selectTab(id) }
                            .contextMenu { tabMenu(window, pane: pane) }
                    }
                }
            } else {
                Text("Empty pane. New windows can open here.").font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            paneMenu
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(focusedPane ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: focusedPane ? 1.5 : 1))
    }

    @ViewBuilder private func tabMenu(_ window: LiveWindow, pane: Pane) -> some View {
        Button("Close") { model.closeTabs([window.id]) }
        Button("Close Other Tabs") { model.closeOtherTabs(window.id) }.disabled(pane.tabs.count < 2)
        Button("Close Tabs to the Right") { model.closeTabsToRight(window.id) }.disabled(pane.tabs.last == window.id)
        Divider()
        Button("Split Right") { model.splitTab(window.id, axis: .horizontal) }.disabled(pane.tabs.count < 2)
        Button("Split Below") { model.splitTab(window.id, axis: .vertical) }.disabled(pane.tabs.count < 2)
        Divider()
        Button("Keep Floating") { model.setBehavior(window.id, .floating, saveRule: false) }
        Button("Always Float \(window.appName)") { model.setBehavior(window.id, .floating, saveRule: true) }
        Menu("Move to Stage") {
            ForEach(model.state.stages) { stage in Button(stage.name) { model.send(window.id, to: stage.id) }.disabled(stage.id == key.stage) }
        }
        Menu("Move to Display") {
            ForEach(model.orderedDisplays) { display in Button(display.name) { model.sendWindow(window.id, to: display) }.disabled(display.id == key.display) }
        }.disabled(model.displays.count < 2)
    }

    private var paneMenu: some View {
        Menu {
            Button("Split Side by Side") { model.paneAction(key) { layout, _ in layout.split(paneID, axis: .horizontal, moving: nil) } }
            Button("Split Top and Bottom") { model.paneAction(key) { layout, _ in layout.split(paneID, axis: .vertical, moving: nil) } }
            Button(model.layouts[key]?.zoomed == paneID ? "Restore Panes" : "Zoom Pane") { model.paneAction(key) { layout, _ in layout.toggleZoom(paneID) } }
            Divider()
            Button("Even Out Panes") { model.paneAction(key) { layout, _ in layout.evenOut() } }
            Button("Reflow as Grid") { model.paneAction(key) { layout, display in layout.reflow(aspect: display.area.width / max(display.area.height, 1)) } }
            Button("Undo Layout Change") { model.undoLayout(key: key) }
            Menu("Move Selected Tab to Display") {
                ForEach(model.orderedDisplays) { display in
                    Button(display.name) { if let id = model.layouts[key]?.root.pane(paneID)?.selected { model.sendWindow(id, to: display) } }
                        .disabled(display.id == key.display)
                }
            }.disabled(model.displays.count < 2)
            Divider()
            Button("Close Pane") { model.paneAction(key) { layout, _ in layout.removePane(paneID) } }.disabled((model.layouts[key]?.root.panes.count ?? 1) < 2)
            Button("Switch Display to Freeform") { model.toggleWindowMode(on: model.displays.first { $0.id == key.display }) }
        } label: { Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24).help("Pane actions")
    }
}

private struct TabView: View {
    let window: LiveWindow
    let selected: Bool
    let tooSmall: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon = window.icon { Image(nsImage: icon).resizable().scaledToFit().frame(width: 14, height: 14) }
            Text(window.title.isEmpty ? window.appName : window.title).font(.system(size: 11, weight: selected ? .semibold : .regular)).lineLimit(1)
            if tooSmall {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(.orange)
                    .help("\(window.appName) cannot shrink to this pane, so it overlaps its neighbour. Choose Keep Floating to take it out of the layout.")
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(selected ? Color.primary.opacity(0.12) : hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(window.title.isEmpty ? window.appName : "\(window.appName): \(window.title)")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

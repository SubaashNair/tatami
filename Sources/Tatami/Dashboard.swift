import SwiftUI
import AppKit
import TatamiCore

enum Theme {
    static let background = Color(red: 0.96, green: 0.96, blue: 0.94)
    static let sidebar = Color(red: 0.93, green: 0.94, blue: 0.91)
    static let ink = Color(red: 0.15, green: 0.20, blue: 0.17)
    static let muted = Color(red: 0.46, green: 0.49, blue: 0.45)
    static let accent = Color(red: 0.28, green: 0.40, blue: 0.28)
    static let line = Color.black.opacity(0.07)
}

struct Dashboard: View {
    @ObservedObject var model: AppModel
    @State private var newStage = false
    @State private var saving = false
    @State private var name = ""
    @State private var rename: Stage?
    @State private var pendingLoad: SavedWorkspace?
    @State private var pendingDelete: Stage?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(spacing: 0) {
                toolbar
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if !model.trusted { permissionBanner }
                        switch model.selection {
                        case "saved": savedWorkspaces
                        case "rules": routing
                        case "ai": aiOrganizer
                        case "settings": settings
                        default: stages
                        }
                    }.padding(32)
                }
                statusBar
            }.frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .frame(minWidth: 1000, minHeight: 700)
        .preferredColorScheme(.light)
        .sheet(isPresented: $newStage) {
            nameSheet(title: "A place for your next project", subtitle: "Give your Stage a short, memorable name.", button: "Create Stage") {
                model.addStage(name); newStage = false
            }
        }
        .sheet(isPresented: $saving) {
            nameSheet(title: "Keep this arrangement", subtitle: "Save your Stages and the positions of currently open windows.", button: "Save Workspace") {
                model.saveWorkspace(name); saving = false
            }
        }
        .sheet(item: $rename) { stage in
            nameSheet(title: "Rename Stage", subtitle: "Your windows and layout will stay together.", button: "Save Name") {
                model.renameStage(stage.id, name: name); rename = nil
            }
        }
        .sheet(item: $pendingLoad) { workspace in
            VStack(alignment: .leading, spacing: 20) {
                Label("Load workspace", systemImage: "square.stack.3d.up").font(.title2.weight(.semibold))
                Text(workspace.name).font(.largeTitle.weight(.medium))
                Text("\(workspace.stages.count) Stages · \(workspace.windows.count) saved windows").foregroundStyle(Theme.muted)
                Text("Tatami will match currently open windows by app and title, restore their positions, and replace your current Stage arrangement. Closed or renamed windows will be skipped. You can undo this load.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { pendingLoad = nil }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Load Workspace") { model.load(workspace); pendingLoad = nil; model.selection = "stages" }.buttonStyle(.borderedProminent)
                }
            }.padding(32).frame(width: 450)
        }
        .alert("Remove Stage?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Remove", role: .destructive) { if let stage = pendingDelete { model.deleteStage(stage.id) }; pendingDelete = nil }
        } message: { Text("Its windows will move to another Stage. You can undo this change.") }
        .alert("Tatami needs your attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.split.2x2.fill").font(.system(size: 29, weight: .medium)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("tatami").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-1)
                    Text("A little room to focus.").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }.padding(.top, 34).padding(.bottom, 39).padding(.horizontal, 22)
            Text("YOUR DESK").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(Theme.muted).padding(.horizontal, 24).padding(.bottom, 12)
            nav("stages", "Stages", "square.grid.2x2", badge: "\(model.state.stages.count)")
            nav("saved", "Saved Workspaces", "bookmark", badge: model.state.saved.isEmpty ? nil : "\(model.state.saved.count)")
            nav("rules", "App Routing", "arrow.triangle.branch")
            nav("ai", "AI Organizer", "sparkles")
            nav("settings", "Preferences", "slider.horizontal.3")
            Divider().padding(.horizontal, 22).padding(.vertical, 24)
            HStack { Text("STAGES").font(.system(size: 10, weight: .semibold)).tracking(1.6); Spacer(); Button { name = ""; newStage = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("Create a Stage") }
                .foregroundStyle(Theme.muted).padding(.horizontal, 24).padding(.bottom, 12)
            ForEach(Array(model.state.stages.enumerated()), id: \.element.id) { index, stage in
                Button { model.switchStage(stage.id); model.selection = "stages" } label: {
                    HStack(spacing: 10) {
                        Circle().fill(stage.id == model.state.activeStageID ? Theme.accent : Theme.muted.opacity(0.3)).frame(width: 6, height: 6)
                        Text(stage.name).lineLimit(1)
                        Spacer()
                        Text("\(model.state.shortcutPreset.stageModifiers)\(index + 1)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                    }.padding(.horizontal, 14).padding(.vertical, 11)
                        .background(stage.id == model.state.activeStageID ? Color.white.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.horizontal, 12)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Label(model.managing ? "Your desk is connected" : "Your desk, at your pace", systemImage: model.managing ? "checkmark.circle.fill" : "leaf")
                    .font(.system(size: 12, weight: .medium))
                Text(model.managing ? "Stage shortcuts are active. Pause anytime to restore all windows." : "Arrange your Stages, then start managing when you're ready.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4)
                Button(model.managing ? "Pause management" : "Start managing") { model.toggleManagement() }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            }.padding(16).background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)).padding(16)
            HStack { Circle().fill(model.trusted ? Theme.accent : Color.orange).frame(width: 6, height: 6); Text(model.trusted ? "Accessibility connected" : "Accessibility required"); Spacer() }
                .font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.horizontal, 24).padding(.bottom, 22)
        }.frame(width: 224).background(Theme.sidebar)
    }

    private func nav(_ id: String, _ title: String, _ symbol: String, badge: String? = nil) -> some View {
        Button { model.selection = id } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 14)).frame(width: 18)
                Text(title).font(.system(size: 12, weight: model.selection == id ? .semibold : .regular))
                Spacer()
                if let badge { Text(badge).font(.system(size: 10, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 2).background(.black.opacity(0.05), in: Capsule()) }
            }.padding(.horizontal, 12).padding(.vertical, 12)
                .background(model.selection == id ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 3)
    }

    private var toolbar: some View {
        HStack {
            HStack(spacing: 7) { Image(systemName: "desktopcomputer"); Text("My Mac"); Image(systemName: "chevron.right").font(.system(size: 8)); Text(model.selection == "stages" ? "Stages" : model.selection == "saved" ? "Saved Workspaces" : model.selection == "rules" ? "App Routing" : model.selection == "ai" ? "AI Organizer" : "Preferences").foregroundStyle(Theme.ink) }
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
            Spacer()
            Label("\(model.displays.count) display\(model.displays.count == 1 ? "" : "s")", systemImage: "display.2").font(.system(size: 11)).foregroundStyle(Theme.muted)
            Divider().frame(height: 14).padding(.horizontal, 10)
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Refresh windows")
        }.padding(.horizontal, 32).frame(height: 58).background(.white.opacity(0.4))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var permissionBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: "hand.raised").font(.system(size: 23)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text("Give your windows a place to belong").font(.system(size: 13, weight: .semibold))
                Text("Allow Accessibility to discover, arrange, and switch your app windows. Turn off macOS Stage Manager first.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Connect Tatami") { model.service.requestAccess(); NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
                .buttonStyle(.borderedProminent)
        }.padding(20).background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var stages: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .center) {
                heading("Everything in its place.", "One Stage for each way you work. Switch your whole desk together.")
                Spacer()
                Button { name = ""; newStage = true } label: { Label("New Stage", systemImage: "plus") }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.state.stages.count >= 9)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ForEach(Array(model.state.stages.enumerated()), id: \.element.id) { index, stage in
                    stageCard(stage, index: index)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) { Text(model.state.activeStage.name).font(.system(size: 21, weight: .medium)); pill("FREEFORM") }
                    Text("\(model.activeWindows.count) windows · Native movement, a little more order.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(!model.canUndo)
                Button { name = model.state.activeStage.name + " setup"; saving = true } label: { Label("Save Workspace", systemImage: "bookmark") }
                Button { model.retile() } label: { Label("Arrange", systemImage: "rectangle.grid.2x2") }.disabled(model.activeWindows.isEmpty)
            }.buttonStyle(.bordered)
            HStack(alignment: .top, spacing: 20) {
                windowList.frame(maxWidth: .infinity)
                snapPanel.frame(width: 206)
            }
            HStack(spacing: 9) {
                Image(systemName: "info.circle")
                Text(model.managing ? "Switching Stages moves inactive windows just off screen. Your other apps stay running." : "Management is paused. Stage selection previews your groups without hiding windows.")
            }.font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }

    private func stageCard(_ stage: Stage, index: Int) -> some View {
        let active = stage.id == model.state.activeStageID
        let windows = model.windows.filter { $0.stageID == stage.id }
        return VStack(alignment: .leading, spacing: 0) {
            Button { model.switchStage(stage.id) } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Image(systemName: stage.symbol).font(.system(size: 13)); Text(stage.name).font(.system(size: 13, weight: .semibold)); Spacer(); if active { Circle().fill(Theme.accent).frame(width: 6, height: 6) }; Text("\(index + 1)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted) }
                    GeometryReader { geometry in
                        ZStack {
                            RoundedRectangle(cornerRadius: 7).fill(Theme.sidebar.opacity(0.7))
                            if windows.isEmpty {
                                VStack(spacing: 7) { Image(systemName: "rectangle.dashed").font(.system(size: 25, weight: .ultraLight)); Text("Room for something good").font(.system(size: 10)) }.foregroundStyle(Theme.muted.opacity(0.65))
                            } else {
                                HStack(alignment: .center, spacing: 5) {
                                    ForEach(Array(windows.prefix(3))) { window in
                                        VStack(spacing: 7) {
                                            HStack(spacing: 3) { ForEach(0..<3) { _ in Circle().fill(Theme.muted.opacity(0.22)).frame(width: 3, height: 3) }; Spacer() }
                                            Spacer(minLength: 0)
                                            AppIcon(window: window, size: 22)
                                            Text(window.appName).font(.system(size: 8)).lineLimit(1)
                                            Spacer(minLength: 0)
                                        }.padding(8).frame(maxWidth: .infinity).frame(height: 74).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.line))
                                    }
                                }.padding(12)
                            }
                        }.frame(width: geometry.size.width, height: 105)
                    }.frame(height: 105)
                }.padding(16)
            }.buttonStyle(.plain)
            HStack {
                Text("\(windows.count) windows").font(.system(size: 10)).foregroundStyle(Theme.muted)
                Spacer()
                Menu {
                    Button("Rename") { name = stage.name; rename = stage }
                    Button("Move Left") { model.reorderStage(stage.id, direction: -1) }.disabled(index == 0)
                    Button("Move Right") { model.reorderStage(stage.id, direction: 1) }.disabled(index == model.state.stages.count - 1)
                    Divider()
                    Button("Remove Stage", role: .destructive) { pendingDelete = stage }.disabled(model.state.stages.count == 1)
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20).help("Stage actions")
            }.padding(.horizontal, 16).padding(.bottom, 12)
        }.background(active ? Color.white : Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? Theme.accent.opacity(0.65) : Theme.line, lineWidth: active ? 1.5 : 1))
            .dropDestination(for: String.self) { items, _ in
                guard let value = items.first, let id = UUID(uuidString: value), model.windows.contains(where: { $0.id == id }) else { return false }
                model.send(id, to: stage.id); return true
            }
    }

    private var windowList: some View {
        VStack(spacing: 0) {
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted); TextField("Find a window…", text: $model.search).textFieldStyle(.plain); Spacer(); Text("WINDOWS").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Theme.muted) }
                .font(.system(size: 12)).padding(16)
            Divider()
            if model.activeWindows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: model.trusted ? "macwindow.badge.plus" : "macwindow").font(.system(size: 33, weight: .ultraLight)).foregroundStyle(Theme.muted)
                    Text(model.search.isEmpty ? "A clear space to start." : "No matching windows.").font(.system(size: 15, weight: .medium))
                    Text(model.trusted ? "Open an app here, or send a window from another Stage." : "Connect Accessibility to see your open windows here.").font(.system(size: 11)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).frame(height: 180).padding(18)
            } else {
                ForEach(model.activeWindows) { window in
                    HStack(spacing: 12) {
                        AppIcon(window: window, size: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(window.title.isEmpty ? window.appName : window.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(window.appName + (model.state.excludedBundleIDs.contains(window.bundleID) ? " · Always visible" : window.minimized ? " · Minimized" : "")).font(.system(size: 10)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 4)
                        Button { model.focus(window) } label: { Image(systemName: "arrow.up.forward") }.buttonStyle(.plain).help("Focus window")
                        Menu {
                            Section("Move to Stage") { ForEach(model.state.stages) { stage in Button(stage.name) { model.send(window.id, to: stage.id) } } }
                            Divider()
                            Button(model.state.excludedBundleIDs.contains(window.bundleID) ? "Stage This App" : "Keep App Always Visible") { model.exclude(window.bundleID) }
                            Menu("Route New Windows To") { ForEach(model.state.stages) { stage in Button(stage.name) { model.addRule(for: window, stageID: stage.id) } } }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 19)
                    }.padding(.horizontal, 16).padding(.vertical, 13)
                        .background(model.selectedWindowID == window.id ? Theme.accent.opacity(0.09) : Color.clear)
                        .contentShape(Rectangle()).onTapGesture { model.selectedWindowID = window.id }
                        .draggable(window.id.uuidString)
                    if window.id != model.activeWindows.last?.id { Divider().padding(.leading, 56) }
                }
            }
        }.background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    private var snapPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Image(systemName: "rectangle.split.2x2"); Text("Make some space").font(.system(size: 12, weight: .semibold)) }
            Text(model.selectedWindow?.appName ?? "Select a window to arrange it.").font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(SnapZone.allCases) { zone in
                    Button { model.snap(zone, windowID: model.selectedWindowID) } label: { ZoneGlyph(zone: zone).frame(height: 26).padding(5).background(Theme.sidebar.opacity(0.5), in: RoundedRectangle(cornerRadius: 5)) }
                        .buttonStyle(.plain).help(zone.label).accessibilityLabel(zone.label).disabled(model.selectedWindowID == nil)
                }
            }
            Divider()
            HStack(spacing: 6) { Image(systemName: "keyboard"); Text("⌃⌥ + arrow to snap").font(.system(size: 10)) }.foregroundStyle(Theme.muted)
        }.padding(16).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    private var savedWorkspaces: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { heading("Pick up where you left off.", "Named arrangements for the work you return to."); Spacer(); Button("Save Current Desk") { name = "My workspace"; saving = true }.buttonStyle(.borderedProminent).controlSize(.large) }
            if model.state.saved.isEmpty {
                emptyState("Your first workspace is waiting.", "Arrange your windows, then save this desk to bring it back later.", "bookmark")
            }
            ForEach(model.state.saved) { workspace in
                HStack(spacing: 18) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 24, weight: .light)).foregroundStyle(Theme.accent).frame(width: 46, height: 46).background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(workspace.name).font(.system(size: 16, weight: .medium))
                        Text("\(workspace.stages.count) Stages · \(workspace.windows.count) windows · \(workspace.date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("Preview & Load") { pendingLoad = workspace }.buttonStyle(.bordered)
                    Menu {
                        Button("Rename") {
                            let alert = NSAlert(); alert.messageText = "Rename workspace"
                            let field = NSTextField(string: workspace.name); field.frame = NSRect(x: 0, y: 0, width: 260, height: 24); alert.accessoryView = field
                            alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
                            if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               let i = model.state.saved.firstIndex(where: { $0.id == workspace.id }) {
                                model.state.saved[i].name = String(field.stringValue.prefix(60)); model.persist()
                            }
                        }
                        Button("Delete", role: .destructive) {
                            let alert = NSAlert(); alert.messageText = "Delete \(workspace.name)?"; alert.informativeText = "Your current windows will stay as they are."
                            alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
                            if alert.runModal() == .alertFirstButtonReturn { model.state.saved.removeAll { $0.id == workspace.id }; model.persist() }
                        }
                    } label: { Image(systemName: "ellipsis") }.frame(width: 22)
                }.padding(22).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Stored only on this Mac. This version restores currently open windows; it does not reopen apps or documents.").font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }

    private var routing: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Let your apps find their way.", "Route new windows automatically. The first matching rule wins.")
            if model.state.rules.isEmpty { emptyState("A home for every app.", "Open the ••• menu beside a window and choose Route New Windows To to add your first rule.", "arrow.triangle.branch") }
            ForEach(Array(model.state.rules.enumerated()), id: \.element.id) { index, rule in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Toggle("", isOn: Binding(get: { model.state.rules.first(where: { $0.id == rule.id })?.enabled ?? false }, set: { value in if let i = model.state.rules.firstIndex(where: { $0.id == rule.id }) { model.state.rules[i].enabled = value; model.persist() } })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        Text(rule.appName).font(.system(size: 14, weight: .medium))
                        Image(systemName: "arrow.right").foregroundStyle(Theme.muted)
                        Text(model.state.stages.first(where: { $0.id == rule.stageID })?.name ?? "Stage not found").foregroundStyle(Theme.accent)
                        Spacer()
                        Button { model.state.rules.swapAt(index, index - 1); model.persist() } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Evaluate this rule earlier")
                        Button { model.state.rules.removeAll { $0.id == rule.id }; model.persist() } label: { Image(systemName: "trash") }.help("Delete rule")
                    }
                    TextField("Optional: window title contains…", text: Binding(get: { model.state.rules.first(where: { $0.id == rule.id })?.titleContains ?? "" }, set: { value in if let i = model.state.rules.firstIndex(where: { $0.id == rule.id }) { model.state.rules[i].titleContains = value; model.persist() } })).textFieldStyle(.roundedBorder)
                    Text(rule.bundleID).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                }.padding(20).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var aiOrganizer: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Describe it. Review it. Apply it.", "Your AI provider proposes an arrangement. Nothing moves until you apply, and Undo restores the previous desk.")
            AIOrganizerView(model: model).padding(24).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            Button("Provider and key settings…") { model.selection = "settings" }.buttonStyle(.link)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Make yourself at home.", "Small adjustments for a desk that feels like yours.")
            settingsBox("WORKFLOW") {
                Toggle("Launch Tatami at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                Divider()
                Toggle("Switch Stage when you focus a window from another Stage (Cmd+Tab, Dock)", isOn: Binding(get: { model.state.followActivatedWindows }, set: { model.state.followActivatedWindows = $0; model.persist() }))
                Divider()
                Toggle("Follow a window when sending it to another Stage", isOn: Binding(get: { model.state.followSentWindow }, set: { model.state.followSentWindow = $0; model.persist() }))
                Divider()
                Toggle("Classic shortcuts (Option + number, Option + arrows)", isOn: Binding(get: { model.state.shortcutPreset == .classic }, set: { model.state.shortcutPreset = $0 ? .classic : .standard; model.updateShortcuts() }))
                Text("Shortcuts are active only while management is running. Standard uses Control + Option + 1–9 to switch, adds Shift to send windows, and Control + Option + Command + arrows to cycle, open the dashboard, and arrange. Classic uses Option alone, which blocks typing characters such as ¡ and ™ and replaces word navigation with Option + arrows.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            settingsBox("WINDOW SPACING") {
                HStack { Text("Space between windows"); Spacer(); Text("\(Int(model.state.gap)) pt").foregroundStyle(Theme.muted).monospacedDigit() }
                Slider(value: Binding(get: { model.state.gap }, set: { model.state.gap = $0; model.persist() }), in: 0...40, step: 2)
                Text("Applied the next time you snap or arrange windows.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            AISettingsBox(model: model)
            settingsBox("YOUR DATA") {
                HStack { VStack(alignment: .leading, spacing: 6) { Text("Portable settings"); Text("Stage names, rules, exclusions, and preferences. No live window data.").font(.system(size: 11)).foregroundStyle(Theme.muted) }; Spacer(); Button("Import…") { model.importBackup() }; Button("Export…") { model.exportBackup() } }
                Divider()
                HStack { Text("Local workspace storage"); Spacer(); Button("Show in Finder") { NSWorkspace.shared.open(model.directory) } }
            }
            settingsBox("RECOVERY") {
                HStack { VStack(alignment: .leading, spacing: 6) { Text("Bring your windows back"); Text("Restores windows minimized by Tatami and pauses Stage management.").font(.system(size: 11)).foregroundStyle(Theme.muted) }; Spacer(); Button("Rescue Windows") { model.rescue() } }
                Text("Emergency shortcut while managing: Control + Option + Command + R. macOS Stage Manager should be turned off while using Tatami.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Text("TATAMI 0.1 · LOCAL FIRST\nThis foundation release includes Freeform Stages, snapping, routing, and saved arrangements. It also includes the AI Organizer with your own key or a local model. Tabbed Tiling, display pinning, and Action Wheel are planned next.").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(5)
        }.toggleStyle(.switch).controlSize(.small)
    }

    private func settingsBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.muted)
            content().font(.system(size: 12))
        }.padding(24).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }
    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.system(size: 29, weight: .medium, design: .serif)).tracking(-0.7); Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted) }
    }
    private func pill(_ text: String) -> some View { Text(text).font(.system(size: 8, weight: .semibold)).tracking(0.7).foregroundStyle(Theme.accent).padding(.horizontal, 7).padding(.vertical, 5).background(Theme.accent.opacity(0.08), in: Capsule()) }
    private func emptyState(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        VStack(spacing: 16) { Image(systemName: symbol).font(.system(size: 40, weight: .ultraLight)).foregroundStyle(Theme.accent); Text(title).font(.system(size: 22, weight: .medium, design: .serif)); Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 400) }
            .frame(maxWidth: .infinity).padding(.vertical, 64).background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: model.notice == nil ? "leaf" : "checkmark.circle")
            Text(model.notice ?? "A calmer desk. A clearer mind.").lineLimit(2)
            Spacer()
            if model.notice != nil { Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss status") }
            Text("v0.1").font(.system(size: 10, design: .monospaced))
        }.font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.horizontal, 32).frame(height: 42).background(.white.opacity(0.5))
    }
    private func nameSheet(title: String, subtitle: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.system(size: 24, weight: .medium, design: .serif))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).onSubmit { if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { action() } }
            HStack { Button("Cancel") { newStage = false; saving = false; rename = nil }.keyboardShortcut(.cancelAction); Spacer(); Button(button, action: action).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 60) }
        }.padding(32).frame(width: 430)
    }
}

struct AppIcon: View {
    let window: LiveWindow
    let size: CGFloat
    var body: some View {
        if let image = window.icon { Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size) }
        else { Image(systemName: "app").resizable().frame(width: size, height: size).foregroundStyle(Theme.muted) }
    }
}

struct ZoneGlyph: View {
    let zone: SnapZone
    var body: some View {
        GeometryReader { geometry in
            let unit = zone.unit
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2).stroke(Theme.muted.opacity(0.4), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1).fill(Theme.accent.opacity(0.5))
                    .frame(width: max(1, geometry.size.width * unit.width - 4), height: max(1, geometry.size.height * unit.height - 4))
                    .offset(x: geometry.size.width * unit.minX + 2, y: geometry.size.height * unit.minY + 2)
            }
        }
    }
}

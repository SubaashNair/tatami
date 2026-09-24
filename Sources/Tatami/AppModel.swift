import AppKit
import SwiftUI
import ServiceManagement
import TatamiCore

@MainActor final class AppModel: ObservableObject {
    @Published var state: WorkspaceState
    @Published var windows: [LiveWindow] = []
    @Published var displays: [DisplayInfo] = []
    @Published var trusted = false
    @Published var managing = false
    @Published var selection = "stages"
    @Published var selectedWindowID: UUID?
    @Published var notice: String?
    @Published var error: String?
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var search = ""
    let service: WindowService
    let hotkeys = Hotkeys()
    let directory: URL
    private let stateURL: URL
    private var timer: Timer?
    private var displayObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var undoSnapshot: SavedWorkspace?
    var showDashboard: (() -> Void)?
    var menuChanged: (() -> Void)?

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tatami", isDirectory: true)
        stateURL = directory.appendingPathComponent("workspace.json")
        var initial = WorkspaceState()
        var loadError: String?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let data = try Data(contentsOf: stateURL)
                initial = try JSONDecoder().decode(WorkspaceState.self, from: data)
                try initial.validate()
            }
        } catch {
            initial = WorkspaceState()
            loadError = "Could not load the previous settings: \(error.localizedDescription). The original file was left in place."
        }
        state = initial
        service = WindowService(directory: directory)
        error = loadError
        hotkeys.onAction = { [weak self] action in self?.handle(action) }
    }

    func start() {
        trusted = service.trusted
        if trusted { _ = service.recoverPreviousSession() }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.service.updateDisplays()
                self?.refresh()
                self?.notice = "Display setup changed. Rescue windows can bring misplaced windows back into view."
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.service.updateDisplays(); self?.refresh() }
        }
    }

    func refresh() {
        let wasTrusted = trusted
        trusted = service.trusted
        if wasTrusted && !trusted {
            managing = false; hotkeys.unregister()
            error = "Accessibility access was removed. Stage management is paused. Minimized windows remain available in the Dock; grant access again to restore them."
        }
        if !wasTrusted && trusted {
            _ = service.recoverPreviousSession()
            notice = "Accessibility is connected. You can start managing your desk."
        }
        service.scan(state: state)
        if managing {
            let failures = service.applyVisibility(state: state)
            if failures > 0 { notice = "\(failures) window(s) could not be managed. Their app may not support this action." }
        }
        publish()
    }

    func publish() {
        windows = service.windows; displays = service.displays
        if let id = selectedWindowID, !windows.contains(where: { $0.id == id }) { selectedWindowID = nil }
        menuChanged?()
    }

    func persist() {
        do {
            try state.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: stateURL, options: .atomic)
        } catch { self.error = "Could not save: \(error.localizedDescription)" }
        menuChanged?()
    }

    var activeWindows: [LiveWindow] {
        windows.filter { ($0.stageID == state.activeStageID || state.excludedBundleIDs.contains($0.bundleID)) &&
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.appName.localizedCaseInsensitiveContains(search)) }
    }
    var selectedWindow: LiveWindow? { windows.first { $0.id == selectedWindowID } }
    var canUndo: Bool { undoSnapshot != nil }

    func toggleManagement() {
        guard trusted else { service.requestAccess(); return }
        managing.toggle()
        if managing {
            let conflicts = hotkeys.register(european: state.europeanShortcuts)
            if conflicts > 0 { error = "\(conflicts) shortcuts are already in use. Those shortcuts were not registered." }
            notice = "Stage management is on. Switch with \(state.europeanShortcuts ? "⌃⌥" : "⌥")1–9."
        } else {
            let failures = service.restoreOwnedWindows()
            hotkeys.unregister()
            notice = failures == 0 ? "Management paused. All Tatami-minimized windows were restored." : "Management paused. \(failures) windows could not be restored; use their Dock icons."
        }
        refresh()
    }

    func switchStage(_ id: UUID) {
        guard state.stages.contains(where: { $0.id == id }) else { return }
        state.activeStageID = id; selectedWindowID = nil; search = ""
        if managing { reportFailures(service.applyVisibility(state: state), action: "switch") }
        publish(); persist()
    }

    func addStage(_ name: String) {
        if let stage = state.addStage(name: name) { switchStage(stage.id) }
        else { error = "Use a name from 1–60 characters. This version supports up to nine Stages." }
    }

    func renameStage(_ id: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, let index = state.stages.firstIndex(where: { $0.id == id }) else { return }
        state.stages[index].name = name; persist()
    }

    func reorderStage(_ id: UUID, direction: Int) {
        guard let index = state.stages.firstIndex(where: { $0.id == id }), state.stages.indices.contains(index + direction) else { return }
        state.stages.swapAt(index, index + direction); persist()
    }

    func deleteStage(_ id: UUID) {
        undoSnapshot = snapshot(name: "Before deleting Stage")
        guard let destination = state.removeStage(id) else { return }
        for i in service.windows.indices where service.windows[i].stageID == id { service.windows[i].stageID = destination }
        if managing { reportFailures(service.applyVisibility(state: state), action: "delete Stage") }
        publish(); persist(); notice = "Stage removed. Its windows were moved to \(state.activeStage.name). Undo is available."
    }

    func send(_ windowID: UUID, to stageID: UUID) {
        guard state.stages.contains(where: { $0.id == stageID }), let index = service.windows.firstIndex(where: { $0.id == windowID }) else { return }
        undoSnapshot = snapshot(name: "Before moving window")
        service.windows[index].stageID = stageID
        if state.followSentWindow { state.activeStageID = stageID }
        if managing { reportFailures(service.applyVisibility(state: state), action: "move window") }
        publish(); persist()
        notice = "Window assigned to \(state.stages.first(where: { $0.id == stageID })?.name ?? "Stage")."
    }

    func snap(_ zone: SnapZone, windowID: UUID? = nil) {
        guard let id = windowID ?? service.focusedID() ?? selectedWindowID,
              let window = service.windows.first(where: { $0.id == id }), let display = service.display(for: window.frame) else {
            notice = "Select a window first, or use a snap shortcut from another app."; return
        }
        undoSnapshot = snapshot(name: "Before snapping")
        if !service.move(id, to: zone.frame(in: display.area, gap: state.gap)) { error = "This app could not resize or move the selected window." }
        publish()
    }

    func retile() {
        undoSnapshot = snapshot(name: "Before arranging")
        var failures = 0
        for display in displays {
            let group = service.windows.filter { $0.stageID == state.activeStageID && !state.excludedBundleIDs.contains($0.bundleID) && !$0.minimized && service.display(for: $0.frame)?.id == display.id }
            for (window, frame) in zip(group, Geometry.grid(count: group.count, area: display.area, gap: state.gap)) {
                if !service.move(window.id, to: frame) { failures += 1 }
            }
        }
        reportFailures(failures, action: "arrange windows"); publish(); notice = "Arranged visible windows by display. Undo is available."
    }

    func rescue() {
        managing = false; hotkeys.unregister()
        let failures = service.restoreOwnedWindows()
        for window in service.windows {
            if let display = service.display(for: window.frame) {
                let adjusted = Geometry.visibleFrame(window.frame, in: display.area)
                if adjusted != window.frame { _ = service.move(window.id, to: adjusted) }
            }
        }
        publish()
        notice = failures == 0 ? "Windows restored. Stage management is paused." : "Some apps did not respond. Their minimized windows are still available in the Dock."
    }

    func focus(_ window: LiveWindow) {
        if window.stageID != state.activeStageID { switchStage(window.stageID) }
        service.focus(window.id)
    }

    func snapshot(name: String) -> SavedWorkspace {
        var occurrences: [String: Int] = [:]
        let snapshots = service.windows.map { window -> WindowSnapshot in
            let key = window.bundleID + "\u{0}" + window.title
            let occurrence = occurrences[key, default: 0]; occurrences[key] = occurrence + 1
            return WindowSnapshot(bundleID: window.bundleID, title: window.title, occurrence: occurrence, stageID: window.stageID, frame: window.frame)
        }
        return SavedWorkspace(name: name, stages: state.stages, activeStageID: state.activeStageID, windows: snapshots)
    }

    func saveWorkspace(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, state.saved.count < 100 else { return }
        state.saved.insert(snapshot(name: String(name.prefix(60))), at: 0); persist()
        notice = "Workspace saved on this Mac."
    }

    func load(_ workspace: SavedWorkspace, keepUndo: Bool = true) {
        if keepUndo { undoSnapshot = snapshot(name: "Before loading workspace") }
        _ = service.restoreOwnedWindows()
        state.stages = workspace.stages; state.activeStageID = workspace.activeStageID
        for i in service.windows.indices { service.windows[i].stageID = state.activeStageID }
        var unmatched = 0, failures = 0
        for saved in workspace.windows {
            let candidates = service.windows.indices.filter { service.windows[$0].bundleID == saved.bundleID && service.windows[$0].title == saved.title }
            guard candidates.indices.contains(saved.occurrence) else { unmatched += 1; continue }
            let index = candidates[saved.occurrence]
            service.windows[index].stageID = saved.stageID
            let frame = saved.frame.cgRect
            if let display = service.display(for: frame), !service.move(service.windows[index].id, to: Geometry.visibleFrame(frame, in: display.area)) { failures += 1 }
        }
        if managing { failures += service.applyVisibility(state: state) }
        publish(); persist()
        notice = "Loaded \(workspace.name). \(unmatched) closed or unmatched windows skipped."
        reportFailures(failures, action: "load workspace")
    }

    func undo() { guard let snapshot = undoSnapshot else { return }; load(snapshot, keepUndo: false); undoSnapshot = nil; objectWillChange.send() }

    func exclude(_ bundleID: String) {
        if state.excludedBundleIDs.contains(bundleID) { state.excludedBundleIDs.removeAll { $0 == bundleID } }
        else { state.excludedBundleIDs.append(bundleID) }
        persist(); refresh()
    }

    func addRule(for window: LiveWindow, stageID: UUID, title: String = "") {
        state.rules.append(RoutingRule(bundleID: window.bundleID, appName: window.appName, titleContains: title, stageID: stageID))
        persist(); notice = "New \(window.appName) windows will follow this rule. Existing windows stay where they are."
    }

    func exportBackup() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Tatami-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // No window titles, application paths, or live workspace state in portable backup.
            var copy = state; copy.saved = []
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(copy).write(to: url, options: .atomic); notice = "Settings exported. Saved window layouts stay on this Mac."
        } catch { self.error = error.localizedDescription }
    }

    func importBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 5_000_000 else { throw ValidationError.invalidState }
            var imported = try JSONDecoder().decode(WorkspaceState.self, from: data); try imported.validate()
            let alert = NSAlert(); alert.messageText = "Import Tatami settings?"
            alert.informativeText = "This replaces Stage names, shortcuts preferences, and routing rules. Your saved workspaces remain on this Mac. Window management will pause."
            alert.addButton(withTitle: "Import"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            rescue(); imported.saved = state.saved; state = imported
            for i in service.windows.indices { service.windows[i].stageID = state.activeStageID }
            persist(); publish(); notice = "Settings imported. Start managing when you are ready."
        } catch { self.error = error.localizedDescription }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
        } catch { self.error = "Launch at login requires a packaged app in Applications. \(error.localizedDescription)" }
    }

    func updateShortcuts() {
        persist()
        if managing { let failures = hotkeys.register(european: state.europeanShortcuts); reportFailures(failures, action: "register shortcuts") }
    }

    func shutdown() { timer?.invalidate(); hotkeys.unregister(); _ = service.restoreOwnedWindows(); persist() }
    private func reportFailures(_ count: Int, action: String) { if count > 0 { error = "Could not \(action) for \(count) item(s). Some applications may not support the requested action." } }

    private func handle(_ action: HotkeyAction) {
        switch action {
        case .stage(let index): if state.stages.indices.contains(index) { switchStage(state.stages[index].id) }
        case .send(let index): if state.stages.indices.contains(index), let id = service.focusedID() { send(id, to: state.stages[index].id) }
        case .cycle(let offset):
            let index = state.stages.firstIndex(where: { $0.id == state.activeStageID }) ?? 0
            switchStage(state.stages[(index + offset + state.stages.count) % state.stages.count].id)
        case .snap(let zone): snap(zone)
        case .dashboard: showDashboard?()
        case .retile: retile()
        case .rescue: rescue()
        }
    }
}

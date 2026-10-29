import AppKit
import SwiftUI
import ServiceManagement
import os
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
    @Published var aiPrompt = ""
    @Published var aiState: AIState = .idle
    @Published var aiModels: [String] = []
    var aiTask: Task<Void, Never>?
    /// ref ("w1") → live window, captured when the plan was requested.
    var aiRefs: [String: UUID] = [:]
    var showOrganizer: (() -> Void)?
    var hideOrganizer: (() -> Void)?
    let service: WindowService
    let hotkeys = Hotkeys()
    let directory: URL
    private let stateURL: URL
    private var timer: Timer?
    private var displayObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var appObservers: [NSObjectProtocol] = []
    /// Stage → window last focused there, restored when returning to the Stage (M1 decision 12).
    var lastFocused: [UUID: UUID] = [:]
    var checkpointWork: DispatchWorkItem?
    // TabStack (M3)
    var layouts: [LayoutKey: PaneLayout] = [:]
    var histories: [LayoutKey: LayoutHistory] = [:]
    /// Pre-TabStack frames, restored when a display returns to Freeform. ponytail: in memory only; after a relaunch windows stay tiled-size.
    var freeformFrames: [UUID: CGRect] = [:]
    var expectedFrames: [UUID: CGRect] = [:]
    var minSizeWindows: Set<UUID> = []
    var userEditingLayout = false
    /// Per-window Keep Floating / Manage in Layout choices that were not saved as rules.
    var behaviorOverrides: [UUID: WindowBehavior] = [:]
    var onLayoutsApplied: (() -> Void)?
    /// Layouts of disconnected displays, rebuilt by Restore when the display returns (M3 decision 12).
    var detachedLayouts: [LayoutKey: PaneLayout] = [:]
    /// Windows moved off a disconnected display: window → (display key, original frame), for Restore on reconnect.
    var displaced: [UUID: (display: String, frame: CGRect)] = [:]
    /// Shows the Restore / Keep Current panel (M1 decision 8).
    var onReconnectOffer: ((ReconnectOffer) -> Void)?
    var sleepObserver: NSObjectProtocol?
    /// Our own switch moves focus around; ignore focus events until it settles.
    private var suppressFollowUntil = Date.distantPast
    private let followSuppression: TimeInterval = 1
    /// Events drive updates; this rescan only catches notifications apps fail to send (M1 decision 3).
    private let safetyNetInterval: TimeInterval = 5
    var undoSnapshot: SavedWorkspace?
    var showDashboard: (() -> Void)?
    var showStagesBar: (() -> Void)?
    @Published var sortPreview: SortPreview?
    /// No settings file existed at launch: offer to sort windows once Accessibility is available (ONB-06).
    var isFirstRun = false
    var onStageSwitched: ((_ index: Int, _ stage: Stage) -> Void)?
    var onDockPreferenceChanged: (() -> Void)?
    let scrollSwitcher = ScrollSwitcher()
    var menuChanged: (() -> Void)?

    init() {
        // TATAMI_DATA_DIR isolates integration tests from the user's real state.
        directory = ProcessInfo.processInfo.environment["TATAMI_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tatami", isDirectory: true)
        stateURL = directory.appendingPathComponent("workspace.json")
        var initial = WorkspaceState()
        var loadError: String?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            isFirstRun = !FileManager.default.fileExists(atPath: stateURL.path)
            if !isFirstRun {
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
        scrollSwitcher.onSwitch = { [weak self] offset in guard let self else { return }; self.switchStage(self.state.stageID(offset: offset)) }
    }

    func start() {
        trusted = service.trusted
        if trusted { _ = service.recoverPreviousSession() }
        service.stateProvider = { [weak self] in self?.state ?? WorkspaceState() }
        applyLaunchAtLoginDefault()
        service.onWindowsChanged = { [weak self] notifications in
            self?.windowsChanged()
            if notifications.contains(kAXFocusedWindowChangedNotification) || notifications.contains(kAXMainWindowChangedNotification) { self?.followFocus() }
        }
        Task { await refreshNow(); restoreCheckpoint(); offerFirstRunSort() }
        timer = Timer.scheduledTimer(withTimeInterval: safetyNetInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.displaysChanged() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // displaysChanged() diffs the old and new display lists itself; updating them first would hide a change from it.
            Task { @MainActor in self?.displaysChanged(); self?.refresh() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        appObservers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pauseIfConflictingManagerStarted(); self?.refresh() }
            }
        }
        sleepObserver = workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.writeCheckpoint() }
        }
        // Cmd+Tab and Dock clicks activate an app without changing its focused window.
        appObservers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.followFocus() }
        })
    }

    /// Fire-and-forget: the scan runs on the AX thread and results land on the main thread.
    func refresh() { Task { await refreshNow() } }

    func refreshNow() async {
        let wasTrusted = trusted
        trusted = service.trusted
        if wasTrusted && !trusted {
            managing = false; service.managing = false; hotkeys.unregister(); scrollSwitcher.stop()
            onLayoutsApplied?()  // hides the tab bars
            error = "Accessibility access was removed, so Tatami cannot move windows. Grant access again and parked windows return automatically. Until then, minimized windows are in the Dock, and Window → Fill in an app's menu brings a window back on screen."
        }
        if !wasTrusted && trusted {
            _ = service.recoverPreviousSession()
            notice = "Accessibility is connected. You can start managing your desk."
        }
        await service.scan()
        windowsChanged()
        offerFirstRunSort()  // no-op unless this is the first run and windows are now visible
    }

    /// After any scan: new windows may need hiding (routing to inactive Stages), then the UI updates.
    func windowsChanged() {
        if managing {
            let structural = syncLayouts()
            let edited = checkLayoutEdits()
            if structural || edited { applyLayouts() } else {
                let failures = applyVisibility()
                if failures > 0 { notice = "\(failures) window(s) could not be managed. Their app may not support this action." }
            }
        }
        publish()
    }

    func publish() {
        windows = service.windows; displays = service.displays
        if let id = selectedWindowID, !windows.contains(where: { $0.id == id }) { selectedWindowID = nil }
        scheduleCheckpoint()
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

    /// Two managers moving the same windows fight each other and can strand windows off-screen.
    static let conflictingManagers = ["bobko.aerospace": "AeroSpace", "com.koekeishiya.yabai": "yabai", "com.amethyst.Amethyst": "Amethyst",
                                      "app.betterstage.BetterStage": "BetterStage", "com.betterstage.app": "BetterStage"]

    func runningConflictingManager() -> String? {
        let running = NSWorkspace.shared.runningApplications
        if let app = running.first(where: { Self.conflictingManagers[$0.bundleIdentifier ?? ""] != nil }) { return Self.conflictingManagers[app.bundleIdentifier!] }
        // yabai and AeroSpace can also run as bare executables.
        return running.contains { ["yabai", "AeroSpace"].contains($0.executableURL?.lastPathComponent ?? "") } ? "another tiling window manager" : nil
    }

    /// A tiling manager started while Tatami manages: step aside instead of fighting over windows.
    func pauseIfConflictingManagerStarted() {
        guard managing, ProcessInfo.processInfo.environment["TATAMI_AUTOSTART"] != "1", let other = runningConflictingManager() else { return }
        toggleManagement()
        error = "\(other) started, so Tatami paused and restored every window it had hidden. Two window managers moving the same windows fight each other. Quit \(other) and choose Start managing to continue."
    }

    func toggleManagement() {
        guard trusted else { service.requestAccess(); return }
        if !managing, let other = runningConflictingManager(), ProcessInfo.processInfo.environment["TATAMI_AUTOSTART"] != "1" {
            let alert = NSAlert()
            alert.messageText = "\(other) is running"
            alert.informativeText = "Tatami and \(other) both move windows, and will fight over them. Quit \(other) first, or start anyway if you have configured it to ignore the apps Tatami manages."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Start Anyway")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        managing.toggle()
        service.managing = managing
        if managing {
            let conflicts = hotkeys.register(preset: state.shortcutPreset, scopeCommandBacktick: state.scopeCommandBacktick)
            if !scrollSwitcher.start(preset: state.shortcutPreset) {
                error = "Scroll switching is unavailable because macOS did not allow Tatami to watch scroll events. Shortcuts still work; try Pause and Start managing again."
            }
            if conflicts > 0 { error = "\(conflicts) shortcuts are already in use. Those shortcuts were not registered." }
            notice = "Stage management is on. Switch with \(state.shortcutPreset.stageModifiers)1–9."
        } else {
            let failures = service.restoreOwnedWindows()
            hotkeys.unregister(); scrollSwitcher.stop()
            notice = failures == 0 ? "Management paused. Every window Tatami hid is back." : "Management paused. \(failures) windows could not be restored; use Rescue Windows or their Dock icons."
        }
        applyLayouts()  // tiles on start (layouts may come from the checkpoint); only hides tab bars on pause
        refresh()
    }

    private static let log = Logger(subsystem: "app.tatami.mac", category: "engine")
    private static let signposter = OSSignposter(logger: log)

    func switchStage(_ id: UUID) {
        guard state.stages.contains(where: { $0.id == id }) else { return }
        state.activeStageID = id; selectedWindowID = nil; search = ""
        if managing {
            // Measured, not assumed (M1 decision 7): view in Console or Instruments › os_signpost.
            let interval = Self.signposter.beginInterval("switchStage")
            let start = ContinuousClock.now
            suppressFollowUntil = Date().addingTimeInterval(followSuppression)
            reportFailures(applyVisibility(), action: "switch")
            applyLayouts()  // also moves tab bars to the new Stage (or hides them)
            focusAfterSwitch(to: id)
            Self.signposter.endInterval("switchStage", interval)
            let ms = (ContinuousClock.now - start) / .milliseconds(1)
            if state.showSwitchIndicator, let index = state.stages.firstIndex(where: { $0.id == id }) { onStageSwitched?(index, state.stages[index]) }
            Self.log.info("Stage switch took \(ms, format: .fixed(precision: 1)) ms for \(self.service.windows.count) windows")
        }
        publish(); persist()
    }

    /// Typing must never go to a parked window: focus something visible on the new Stage, or the desktop.
    private func focusAfterSwitch(to stage: UUID) {
        let candidates = service.windows.filter { $0.stageID == stage && $0.hidden == nil && !$0.minimized }
        if let id = lastFocused[stage], candidates.contains(where: { $0.id == id }) { service.focus(id) }
        else if let first = candidates.first { service.focus(first.id) }
        else { NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate() }
    }

    /// Follow activated windows (M1 decision 11), and remember the last focused window per Stage.
    func followFocus() {
        guard managing, Date() >= suppressFollowUntil, let id = service.focusedID(),
              let window = service.windows.first(where: { $0.id == id }) else { return }
        lastFocused[window.stageID] = id
        if noteLayoutFocus(id) { return }  // a tab on the active Stage: select it rather than switching
        guard window.stageID != state.activeStageID, !state.excludedBundleIDs.contains(window.bundleID),
              state.followActivatedWindows, state.stages.contains(where: { $0.id == window.stageID }) else { return }
        switchStage(window.stageID)
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

    /// Drag-to-reorder in the Stages Bar. Number shortcuts follow the new order.
    func moveStage(_ id: UUID, before target: UUID) {
        guard id != target, let from = state.stages.firstIndex(where: { $0.id == id }) else { return }
        let stage = state.stages.remove(at: from)
        let to = state.stages.firstIndex(where: { $0.id == target }) ?? state.stages.count
        state.stages.insert(stage, at: from <= to ? to + 1 : to)
        persist(); publish()
    }

    /// Dropping a window on the "+" card: create a Stage and send the window there without switching.
    func sendToNewStage(_ windowID: UUID) {
        guard let stage = state.addStage(name: state.nextStageName()) else { error = "Tatami supports up to nine Stages."; return }
        persist()
        send(windowID, to: stage.id)
    }

    func deleteStage(_ id: UUID) {
        let before = snapshot(name: "Before deleting Stage")
        guard let destination = state.removeStage(id) else { return }  // a refused delete must not replace the current undo
        undoSnapshot = before
        for i in service.windows.indices where service.windows[i].stageID == id { service.windows[i].stageID = destination }
        if managing { reportFailures(applyVisibility(), action: "delete Stage") }
        publish(); persist(); notice = "Stage closed. Its windows moved to \(state.activeStage.name). Undo is available."
    }

    /// Merge All (M2 decision 8). Undo restores every Stage and assignment.
    func mergeAll() {
        guard state.stages.count > 1 else { return }
        undoSnapshot = snapshot(name: "Before merging Stages")
        let first = state.mergeAll()
        for i in service.windows.indices { service.windows[i].stageID = first }
        if managing { reportFailures(applyVisibility(), action: "merge Stages") }
        publish(); persist(); notice = "All Stages merged into \(state.activeStage.name). Undo is available."
    }

    func send(_ windowID: UUID, to stageID: UUID) {
        guard state.stages.contains(where: { $0.id == stageID }), let index = service.windows.firstIndex(where: { $0.id == windowID }) else { return }
        undoSnapshot = snapshot(name: "Before moving window")
        let previousStage = state.activeStageID
        service.windows[index].stageID = stageID
        if state.followSentWindow { state.activeStageID = stageID }
        if managing {
            // The sent window keeps focus while parked; without this, follow-on-focus would chase it.
            suppressFollowUntil = Date().addingTimeInterval(followSuppression)
            reportFailures(applyVisibility(), action: "move window")
            if state.activeStageID != previousStage { applyLayouts() }  // tab bars and frames follow the new Stage
            if service.windows[index].stageID != state.activeStageID { focusAfterSwitch(to: state.activeStageID) }
        }
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
        managing = false; service.managing = false; hotkeys.unregister(); scrollSwitcher.stop()
        let failures = service.restoreOwnedWindows()
        for window in service.windows {
            if let display = service.display(for: window.frame) {
                let adjusted = Geometry.visibleFrame(window.frame, in: display.area)
                if adjusted != window.frame { _ = service.move(window.id, to: adjusted) }
            }
        }
        onLayoutsApplied?()  // hides the tab bars now that managing is off
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
            return WindowSnapshot(bundleID: window.bundleID, title: window.title, occurrence: occurrence, stageID: window.stageID, frame: window.realFrame)
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
        if managing { failures += applyVisibility() }
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
            // AI endpoints are not portable: an imported file must never redirect keys or skip the disclosure.
            var copy = state; copy.saved = []; copy.ai = nil
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
            rescue(); imported.saved = state.saved; imported.ai = state.ai; state = imported
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
        if managing { let failures = hotkeys.register(preset: state.shortcutPreset, scopeCommandBacktick: state.scopeCommandBacktick); scrollSwitcher.stop(); scrollSwitcher.start(preset: state.shortcutPreset); reportFailures(failures, action: "register shortcuts") }
    }

    func shutdown() { timer?.invalidate(); hotkeys.unregister(); scrollSwitcher.stop(); _ = service.restoreOwnedWindows(); writeCheckpoint(); persist() }
    func reportFailures(_ count: Int, action: String) { if count > 0 { error = "Could not \(action) for \(count) item(s). Some applications may not support the requested action." } }

    private func handle(_ action: HotkeyAction) {
        switch action {
        case .stage(let index): if state.stages.indices.contains(index) { switchStage(state.stages[index].id) }
        case .send(let index): if state.stages.indices.contains(index), let id = service.focusedID() { send(id, to: state.stages[index].id) }
        case .cycle(let offset): switchStage(state.stageID(offset: offset))
        case .snap(let zone): if !snapInLayout(zone) { snap(zone) }
        case .stagesBar: showStagesBar?()
        case .newStage: addStage(state.nextStageName())
        case .closeStage: deleteStage(state.activeStageID)
        case .mergeAll: mergeAll()
        case .cycleAppWindows(let offset): cycleAppWindows(offset)
        case .cycleMode: toggleWindowMode()
        case .focusPane(let direction): focusPane(direction)
        case .moveToPane(let direction): moveToPane(direction)
        case .tab(let offset): mutateLayout { layout, _ in layout.cycleTab(offset) }
        case .zoomPane: mutateLayout { layout, _ in layout.toggleZoom(layout.focused) }
        case .splitPane(let axis): mutateLayout { layout, _ in
            if let pane = layout.root.pane(layout.focused), let selected = pane.selected, pane.tabs.count > 1 { layout.split(pane.id, axis: axis, moving: selected) }
            else { layout.split(layout.focused, axis: axis, moving: nil) }
        }
        case .resizePane(let fraction): mutateLayout { layout, _ in layout.resize(layout.focused, by: fraction) }
        case .reflow: mutateLayout { layout, display in layout.reflow(aspect: display.area.width / max(display.area.height, 1)) }
        case .undoLayout: undoLayout()
        case .raiseFloats: raiseFloats(activate: true)
        case .sendToDisplay(let offset): sendFocusedWindowToDisplay(offset: offset)
        case .retile: if layouts[LayoutKey(stage: state.activeStageID, display: targetDisplay()?.id ?? "")] != nil { mutateLayout { layout, _ in layout.evenOut() } } else { retile() }
        case .rescue: rescue()
        case .organizer: showOrganizer?()
        }
    }
}

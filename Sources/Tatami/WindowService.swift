import AppKit
import ApplicationServices
import TatamiCore

struct LiveWindow: Identifiable {
    let id: UUID
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String
    let appName: String
    var windowNumber: UInt32?
    var title: String
    var frame: CGRect
    var minimized: Bool
    var stageID: UUID
    /// Set while Tatami hides the window for an inactive Stage. Holds the frame to restore.
    var hidden: HiddenState?
    var realFrame: CGRect { hidden?.realFrame ?? frame }
    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
}

enum HiddenState {
    /// Moved to a display corner (M1 decision 1).
    case parked(real: CGRect)
    /// Fallback when a window refuses to leave the screen or no corner is free.
    case minimized(real: CGRect)
    var realFrame: CGRect { switch self { case .parked(let real), .minimized(let real): real } }
}

struct DisplayInfo: Identifiable {
    let id: String
    let name: String
    let area: CGRect
    let fullFrame: CGRect
}

struct RecoveryEntry: Codable {
    let pid: Int32
    let bundleID: String
    let title: String
    let frame: Rect
    var windowNumber: UInt32?
    /// Nil in 0.1 journals, which only minimized.
    var parked: Bool?
}

@MainActor final class WindowService {
    var windows: [LiveWindow] = []
    var displays: [DisplayInfo] = []
    let ax = AXThread()
    private var observers: AXObservers!
    private let journalURL: URL
    /// Journal entries from the previous session that could not be restored yet.
    private var unrecovered: [RecoveryEntry] = []
    /// Supplies routing rules and the active Stage for windows discovered by events.
    var stateProvider: () -> WorkspaceState = { WorkspaceState() }
    /// Called on the main thread after an event-driven rescan merged new window data.
    var onWindowsChanged: ((_ notifications: Set<String>) -> Void)?
    private var pendingPids: Set<pid_t> = []
    private var pendingNotifications: Set<String> = []
    private var needsFullScan = false
    private var flushScheduled = false
    /// Moves and resizes fire continuously during drags; coalesce them into one rescan.
    private let eventCoalescing: TimeInterval = 0.05
    /// Tatami must not move anything while paused, not even to rescue windows.
    var managing = false
    /// Windows present at launch belong to their previous state (or another manager); only later arrivals are rescued.
    private var initialScanDone = false
    /// Integration tests scope Tatami to specific apps so the user's real windows are never touched.
    private let onlyBundles = ProcessInfo.processInfo.environment["TATAMI_ONLY_BUNDLES"].map { Set($0.split(separator: ",").map(String.init)) }
    /// macOS moves windows itself around display changes and wake; for a short while, a parked window
    /// found on screen was put there by macOS, not rescued by the user, so it is re-parked.
    private var displaysChangedAt = Date.distantPast
    private let displayChangeGrace: TimeInterval = 3
    /// Bumped on every write so a scan that started before it cannot overwrite fresher frames.
    private var writeGeneration = 0

    init(directory: URL) {
        journalURL = directory.appendingPathComponent("recovery.json")
        ax.perform { AX.configureGlobalTimeout() }
        observers = AXObservers(thread: ax) { [weak self] pid, notification in
            MainActor.assumeIsolated { self?.handleEvent(pid: pid, notification: notification) }
        }
        updateDisplays()
    }

    var trusted: Bool { AXIsProcessTrusted() }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func updateDisplays() {
        displaysChangedAt = Date()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        let screens = NSScreen.screens
        // Hardware identity survives port changes and replugging (M1 decision 4).
        let fingerprints = screens.enumerated().map { index, screen -> DisplayFingerprint in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let displayID = number?.uint32Value ?? 0
            let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
            let uuid = cfUUID.map { CFUUIDCreateString(nil, $0) as String } ?? "display-\(index)"
            return DisplayFingerprint(vendor: CGDisplayVendorNumber(displayID), model: CGDisplayModelNumber(displayID), serial: CGDisplaySerialNumber(displayID),
                                      uuid: uuid, frame: Geometry.accessibilityFrame(screen.frame, primaryHeight: primaryHeight))
        }
        let keys = DisplayFingerprint.keys(for: fingerprints)
        displays = screens.indices.map { i in
            DisplayInfo(id: keys[i], name: screens[i].localizedName,
                        area: Geometry.accessibilityFrame(screens[i].visibleFrame, primaryHeight: primaryHeight), fullFrame: fingerprints[i].frame)
        }
    }

    private func regularApps() -> [AppInfo] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  onlyBundles.map({ $0.contains(app.bundleIdentifier ?? "") }) ?? true else { return nil }
            return AppInfo(pid: app.processIdentifier, bundleID: app.bundleIdentifier ?? "pid.\(app.processIdentifier)", name: app.localizedName ?? "Application")
        }
    }

    // MARK: scanning (off the main thread)

    func scan() async {
        guard trusted else { return }
        let apps = regularApps()
        let observers = observers!, generation = writeGeneration
        let scanned = await ax.run {
            observers.sync(pids: Set(apps.map(\.pid)))
            let result = AXScanner.scan(apps)
            observers.watch(result.windows)
            return result
        }
        // Read the settings now, after the await: a Stage switch during the scan must not be overwritten by an old copy.
        merge(scanned, only: nil, state: stateProvider(), stale: generation != writeGeneration)
    }

    private func rescan(pids: Set<pid_t>) async {
        let apps = regularApps().filter { pids.contains($0.pid) }
        let observers = observers!, generation = writeGeneration
        let scanned = await ax.run {
            let result = AXScanner.scan(apps)
            observers.watch(result.windows)
            return result
        }
        merge(scanned, only: pids, state: stateProvider(), stale: generation != writeGeneration)
    }

    private func handleEvent(pid: pid_t, notification: String) {
        // A destroyed window can no longer report its pid; rescan everything.
        if pid <= 0 { needsFullScan = true } else { pendingPids.insert(pid) }
        pendingNotifications.insert(notification)
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + eventCoalescing) { [weak self] in
            MainActor.assumeIsolated { self?.flushEvents() }
        }
    }

    private func flushEvents() {
        let pids = pendingPids, full = needsFullScan, notifications = pendingNotifications
        pendingPids = []; pendingNotifications = []; needsFullScan = false; flushScheduled = false
        Task {
            if full { await scan() } else { await rescan(pids: pids) }
            onWindowsChanged?(notifications)
        }
    }

    private func isSame(_ scanned: ScannedWindow, _ window: LiveWindow) -> Bool {
        if let a = scanned.windowNumber, let b = window.windowNumber { return scanned.pid == window.pid && a == b }
        return CFEqual(scanned.element, window.element)
    }

    /// Merges on the main thread against current state, so changes made while a scan was running survive.
    /// A stale scan (a write happened meanwhile) only adds and removes windows; its frames are out of date.
    private func merge(_ scan: ScanResult, only pids: Set<pid_t>?, state: WorkspaceState, stale: Bool) {
        var merged = pids.map { pids in windows.filter { !pids.contains($0.pid) } } ?? []
        var reveal: [UUID] = [], rescue: [(UUID, CGRect)] = [], repark: [UUID] = []
        let displaysSettling = Date().timeIntervalSince(displaysChangedAt) < displayChangeGrace
        let screens = displays.map(\.fullFrame)
        for found in scan.windows {
            if var existing = windows.first(where: { isSame(found, $0) }) {
                existing.title = found.title
                existing.windowNumber = found.windowNumber ?? existing.windowNumber
                if !stale {
                    existing.frame = found.frame
                    existing.minimized = found.minimized
                    // Restoring from the Dock, or dragging a parked window back, is an explicit escape hatch.
                    switch existing.hidden {
                    case .parked where !ParkPlanner.isParked(found.frame, displays: screens) && displaysSettling:
                        repark.append(existing.id)
                    case .minimized where !found.minimized, .parked where !ParkPlanner.isParked(found.frame, displays: screens):
                        existing.hidden = nil; existing.stageID = state.activeStageID
                    default: break
                    }
                }
                if existing.hidden != nil && state.excludedBundleIDs.contains(found.bundleID) { reveal.append(existing.id) }
                merged.append(existing)
            } else {
                let window = LiveWindow(id: UUID(), element: found.element, pid: found.pid, bundleID: found.bundleID, appName: found.appName,
                                        windowNumber: found.windowNumber, title: found.title, frame: found.frame, minimized: found.minimized,
                                        stageID: state.destination(bundleID: found.bundleID, title: found.title) ?? state.activeStageID)
                // An app that quit while parked may reopen its window where it was saved: off-screen.
                if managing, initialScanDone, !found.minimized, ParkPlanner.isParked(found.frame, displays: screens), let area = (display(for: found.frame) ?? displays.first)?.area {
                    rescue.append((window.id, Geometry.visibleFrame(found.frame, in: area)))
                }
                merged.append(window)
            }
        }
        // An app that did not answer in time has unknown windows, not none: keep what we knew, with its Stage and hidden state.
        let kept = Set(ScanMerge.keptAfterFailure(known: windows.map { (id: $0.id, pid: $0.pid) }, merged: Set(merged.map(\.id)), failed: scan.failed))
        merged.append(contentsOf: windows.filter { kept.contains($0.id) })
        windows = merged
        if pids == nil { initialScanDone = true }
        if !reveal.isEmpty { _ = show(windows.indices.filter { reveal.contains(windows[$0].id) }) }
        if managing, !repark.isEmpty { _ = hide(windows.indices.filter { repark.contains(windows[$0].id) }) }
        for (id, frame) in rescue { move(id, to: frame) }
    }

    func display(for frame: CGRect) -> DisplayInfo? {
        displays.max { a, b in
            let ar = a.fullFrame.intersection(frame), br = b.fullFrame.intersection(frame)
            return (ar.isNull ? 0 : ar.width * ar.height) < (br.isNull ? 0 : br.width * br.height)
        }
    }

    // MARK: visibility

    private enum HideResult { case parked(CGRect), minimized, failed }

    /// Shows the target Stage first, then hides the rest, so the desk is never empty (M1 decision 12).
    /// `extraHidden`: windows hidden inside the active Stage, i.e. TabStack background tabs and panes behind a zoom.
    func applyVisibility(state: WorkspaceState, extraHidden: Set<UUID> = []) -> Int {
        guard trusted else { return windows.filter { $0.hidden != nil }.count }
        func visible(_ window: LiveWindow) -> Bool {
            !extraHidden.contains(window.id) && (state.excludedBundleIDs.contains(window.bundleID) || window.stageID == state.activeStageID)
        }
        let showing = windows.indices.filter { windows[$0].hidden != nil && visible(windows[$0]) }
        let hiding = windows.indices.filter { windows[$0].hidden == nil && !windows[$0].minimized && !visible(windows[$0]) }
        return show(showing) + hide(hiding)
    }

    private func show(_ indices: [Int]) -> Int {
        guard !indices.isEmpty else { return 0 }
        let jobs = indices.map { (windows[$0].pid, windows[$0].element, windows[$0].hidden!) }
        writeGeneration += 1
        let results: [Bool] = ax.sync {
            Self.perApp(jobs.map(\.0)) { i in
                let (_, element, hidden) = jobs[i]
                switch hidden {
                case .parked(let real): return AX.setFrame(element, real)
                case .minimized: return AX.setMinimized(element, false)
                }
            }
        }
        var failures = 0
        for (i, index) in indices.enumerated() {
            guard results[i] else { failures += 1; continue }
            windows[index].frame = windows[index].realFrame
            windows[index].hidden = nil; windows[index].minimized = false
        }
        try? writeJournal()
        return failures
    }

    private func hide(_ indices: [Int]) -> Int {
        guard !indices.isEmpty else { return 0 }
        let screens = displays.map(\.fullFrame)
        let jobs: [(pid_t, AXUIElement, CGRect?)] = indices.map { index in
            let window = windows[index]
            let home = display(for: window.frame)?.fullFrame ?? screens.first ?? .zero
            return (window.pid, window.element, ParkPlanner.parkFrame(size: window.frame.size, display: home, others: screens.filter { $0 != home }))
        }
        // Journal real frames before any window leaves the screen, so a crash can always put it back.
        for (i, index) in indices.enumerated() {
            let real = windows[index].realFrame  // re-parking keeps the frame the window will return to
            windows[index].hidden = jobs[i].2 == nil ? .minimized(real: real) : .parked(real: real)
        }
        do { try writeJournal() } catch {
            for index in indices { windows[index].hidden = nil }
            return indices.count
        }
        writeGeneration += 1
        let results: [HideResult] = ax.sync {
            Self.perApp(jobs.map(\.0)) { i in
                let (_, element, park) = jobs[i]
                if let park, AX.setPosition(element, park.origin), let actual = AX.frame(of: element), ParkPlanner.isParked(actual, displays: screens) {
                    return .parked(actual)
                }
                // Refused to leave the screen, or no free corner: minimize instead (M1 decision 1).
                return AX.setMinimized(element, true) ? .minimized : .failed
            }
        }
        var failures = 0
        for (i, index) in indices.enumerated() {
            let real = windows[index].realFrame
            switch results[i] {
            case .parked(let actual): windows[index].frame = actual
            case .minimized: windows[index].hidden = .minimized(real: real); windows[index].minimized = true
            case .failed: windows[index].hidden = nil; failures += 1
            }
        }
        try? writeJournal()
        return failures
    }

    /// Runs `body` for every job, in parallel across apps and in order within one app (M1 decision 7).
    nonisolated private static func perApp<R>(_ pids: [pid_t], _ body: (Int) -> R) -> [R] {
        let groups = Array(Dictionary(grouping: pids.indices, by: { pids[$0] }).values)
        var results = [R?](repeating: nil, count: pids.count)
        results.withUnsafeMutableBufferPointer { buffer in
            // Safe: each job writes only its own slot, and groups never share a slot.
            nonisolated(unsafe) let slots = buffer
            DispatchQueue.concurrentPerform(iterations: groups.count) { g in
                AX.withoutEnhancedUI(pid: pids[groups[g][0]]) { for i in groups[g] { slots[i] = body(i) } }
            }
        }
        return results.map { $0! }
    }

    func restoreOwnedWindows() -> Int { show(windows.indices.filter { windows[$0].hidden != nil }) }

    func recoverPreviousSession() -> Int {
        guard trusted, let data = try? Data(contentsOf: journalURL) else { return 0 }
        guard let entries = try? JSONDecoder().decode([RecoveryEntry].self, from: data) else {
            // Never let the next journal write erase a journal that could not be read: keep it for inspection.
            let aside = journalURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: journalURL, to: aside)
            return 0
        }
        // Clamp on the main thread, where display geometry lives; the saved display may be gone.
        let targets = entries.map { entry -> CGRect in
            let frame = entry.frame.cgRect
            return display(for: frame).map { Geometry.visibleFrame(frame, in: $0.area) } ?? frame
        }
        let pending: [RecoveryEntry] = ax.sync {
            var claimed: [AXUIElement] = []
            return zip(entries, targets).filter { entry, target in
                guard let app = NSRunningApplication(processIdentifier: entry.pid), app.bundleIdentifier == entry.bundleID else { return false }
                guard let elements: [AXUIElement] = AX.attribute(AXUIElementCreateApplication(entry.pid), kAXWindowsAttribute) else { return true }
                // Only recover the same live app process. Never launch or close applications.
                // Exactly one window per entry: duplicate titles must not share (and overwrite) a saved frame.
                let match = elements.first { element in
                    guard !claimed.contains(where: { CFEqual($0, element) }) else { return false }
                    if let number = entry.windowNumber { return AX.windowNumber(element) == number }
                    return (AX.attribute(element, kAXTitleAttribute) as String?) == entry.title
                }
                guard let match else { return false }
                claimed.append(match)
                return entry.parked == true ? !AX.setFrame(match, target) : !AX.setMinimized(match, false)
            }.map(\.0)
        }
        unrecovered = pending
        if let data = try? JSONEncoder().encode(pending) { try? data.write(to: journalURL, options: .atomic) }
        return pending.count
    }

    private func writeJournal() throws {
        let entries = windows.compactMap { window -> RecoveryEntry? in
            guard let hidden = window.hidden else { return nil }
            var isParked = false
            if case .parked = hidden { isParked = true }
            return RecoveryEntry(pid: window.pid, bundleID: window.bundleID, title: window.title, frame: Rect(hidden.realFrame),
                                 windowNumber: window.windowNumber, parked: isParked)
        }
        // Entries recovery could not restore stay on record until their app quits, so the next hide cannot erase them.
        unrecovered.removeAll { NSRunningApplication(processIdentifier: $0.pid) == nil }
        try JSONEncoder().encode(entries + unrecovered).write(to: journalURL, options: .atomic)
    }

    // MARK: writes

    /// Changes where a hidden window will reappear, without showing it.
    func setRealFrame(_ id: UUID, _ frame: CGRect) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        switch windows[index].hidden {
        case .parked: windows[index].hidden = .parked(real: frame)
        case .minimized: windows[index].hidden = .minimized(real: frame)
        case nil: break
        }
    }

    /// Visible windows move now; hidden ones reappear at `frame` when their Stage is shown.
    @discardableResult func place(_ id: UUID, at frame: CGRect) -> Bool {
        guard let window = windows.first(where: { $0.id == id }) else { return false }
        if window.hidden != nil { setRealFrame(id, frame); try? writeJournal(); return true }
        return move(id, to: frame)
    }

    @discardableResult func move(_ id: UUID, to frame: CGRect) -> Bool {
        guard let index = windows.firstIndex(where: { $0.id == id }), trusted else { return false }
        let element = windows[index].element
        writeGeneration += 1
        let pid = windows[index].pid
        let (moved, actual) = ax.sync { AX.withoutEnhancedUI(pid: pid) { (AX.setFrame(element, frame), AX.frame(of: element)) } }
        if let actual { windows[index].frame = actual }
        return moved
    }

    /// Live frame straight from the app, bypassing the scan cache (used to tell a window drag from a text drag).
    func liveFrame(_ id: UUID) -> CGRect? {
        guard let element = windows.first(where: { $0.id == id })?.element else { return nil }
        return ax.sync { AX.frame(of: element) }
    }

    func focusedID() -> UUID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let focused: (AXUIElement, UInt32?)? = ax.sync {
            guard let element: AXUIElement = AX.attribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else { return nil }
            return (element, AX.windowNumber(element))
        }
        guard let (element, number) = focused else { return nil }
        return windows.first { window in
            if let number, let own = window.windowNumber { return window.pid == pid && own == number }
            return CFEqual(window.element, element)
        }?.id
    }

    /// Presses the window's own close button, so apps still ask about unsaved work.
    func close(_ id: UUID) {
        guard let element = windows.first(where: { $0.id == id })?.element else { return }
        ax.sync {
            if let button: AXUIElement = AX.attribute(element, kAXCloseButtonAttribute) { AXUIElementPerformAction(button, kAXPressAction as CFString) }
        }
    }

    /// Brings windows forward within their apps without activating them.
    func raise(_ ids: [UUID]) {
        let elements = windows.filter { ids.contains($0.id) && $0.hidden == nil }.map(\.element)
        guard !elements.isEmpty else { return }
        ax.sync { elements.forEach { AXUIElementPerformAction($0, kAXRaiseAction as CFString) } }
    }

    func focus(_ id: UUID) {
        guard let window = windows.first(where: { $0.id == id }) else { return }
        let element = window.element
        ax.sync {
            _ = AX.setMinimized(element, false)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: window.pid)?.activate()
    }
}

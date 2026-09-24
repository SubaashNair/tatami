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
    var minimizedByTatami: Bool = false
    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
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
}

@MainActor final class WindowService {
    var windows: [LiveWindow] = []
    var displays: [DisplayInfo] = []
    let ax = AXThread()
    private var observers: AXObservers!
    private let journalURL: URL
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
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        displays = NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let displayID = number?.uint32Value ?? 0
            let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
            let stableID = uuid.map { CFUUIDCreateString(nil, $0) as String } ?? "display-\(index)"
            return DisplayInfo(id: stableID, name: screen.localizedName,
                               area: Geometry.accessibilityFrame(screen.visibleFrame, primaryHeight: primaryHeight),
                               fullFrame: Geometry.accessibilityFrame(screen.frame, primaryHeight: primaryHeight))
        }
    }

    private func regularApps() -> [AppInfo] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
            return AppInfo(pid: app.processIdentifier, bundleID: app.bundleIdentifier ?? "pid.\(app.processIdentifier)", name: app.localizedName ?? "Application")
        }
    }

    // MARK: scanning (off the main thread)

    func scan(state: WorkspaceState) async {
        guard trusted else { return }
        let apps = regularApps()
        let observers = observers!
        let scanned = await ax.run {
            observers.sync(pids: Set(apps.map(\.pid)))
            let windows = AXScanner.scan(apps)
            observers.watch(windows)
            return windows
        }
        merge(scanned, only: nil, state: state)
    }

    private func rescan(pids: Set<pid_t>, state: WorkspaceState) async {
        let apps = regularApps().filter { pids.contains($0.pid) }
        let observers = observers!
        let scanned = await ax.run {
            let windows = AXScanner.scan(apps)
            observers.watch(windows)
            return windows
        }
        merge(scanned, only: pids, state: state)
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
            if full { await scan(state: stateProvider()) } else { await rescan(pids: pids, state: stateProvider()) }
            onWindowsChanged?(notifications)
        }
    }

    private func isSame(_ scanned: ScannedWindow, _ window: LiveWindow) -> Bool {
        if let a = scanned.windowNumber, let b = window.windowNumber { return scanned.pid == window.pid && a == b }
        return CFEqual(scanned.element, window.element)
    }

    /// Merges on the main thread against current state, so changes made while a scan was running survive.
    private func merge(_ scanned: [ScannedWindow], only pids: Set<pid_t>?, state: WorkspaceState) {
        var merged = pids.map { pids in windows.filter { !pids.contains($0.pid) } } ?? []
        var restore: [AXUIElement] = []
        for found in scanned {
            if var existing = windows.first(where: { isSame(found, $0) }) {
                existing.title = found.title
                existing.windowNumber = found.windowNumber ?? existing.windowNumber
                if !existing.minimizedByTatami { existing.frame = found.frame }
                existing.minimized = found.minimized
                // Unminimizing from the Dock is an explicit escape hatch.
                if existing.minimizedByTatami && !found.minimized { existing.minimizedByTatami = false; existing.stageID = state.activeStageID }
                if state.excludedBundleIDs.contains(found.bundleID), existing.minimizedByTatami {
                    restore.append(found.element); existing.minimizedByTatami = false
                }
                merged.append(existing)
            } else {
                merged.append(LiveWindow(id: UUID(), element: found.element, pid: found.pid, bundleID: found.bundleID, appName: found.appName,
                                         windowNumber: found.windowNumber, title: found.title, frame: found.frame, minimized: found.minimized,
                                         stageID: state.destination(bundleID: found.bundleID, title: found.title) ?? state.activeStageID))
            }
        }
        windows = merged
        if !restore.isEmpty { ax.sync { restore.forEach { _ = AX.setMinimized($0, false) } } }
    }

    func display(for frame: CGRect) -> DisplayInfo? {
        displays.max { a, b in
            let ar = a.fullFrame.intersection(frame), br = b.fullFrame.intersection(frame)
            return (ar.isNull ? 0 : ar.width * ar.height) < (br.isNull ? 0 : br.width * br.height)
        }
    }

    // MARK: visibility

    func applyVisibility(state: WorkspaceState) -> Int {
        guard trusted else { return windows.filter(\.minimizedByTatami).count }
        var failures = 0
        for i in windows.indices {
            let excluded = state.excludedBundleIDs.contains(windows[i].bundleID)
            let visible = excluded || windows[i].stageID == state.activeStageID
            let element = windows[i].element
            if visible && windows[i].minimizedByTatami {
                if ax.sync({ AX.setMinimized(element, false) }) {
                    windows[i].minimizedByTatami = false; windows[i].minimized = false
                } else { failures += 1 }
            } else if !visible && !windows[i].minimized && !windows[i].minimizedByTatami {
                // Journal before changing a window. A crash still leaves native Dock recovery available.
                windows[i].minimizedByTatami = true
                do { try writeJournal() } catch { windows[i].minimizedByTatami = false; failures += 1; continue }
                if ax.sync({ AX.setMinimized(element, true) }) { windows[i].minimized = true }
                else { windows[i].minimizedByTatami = false; failures += 1 }
            }
        }
        try? writeJournal()
        return failures
    }

    func restoreOwnedWindows() -> Int {
        var failures = 0
        for i in windows.indices where windows[i].minimizedByTatami {
            let element = windows[i].element
            if ax.sync({ AX.setMinimized(element, false) }) {
                windows[i].minimizedByTatami = false; windows[i].minimized = false
            } else { failures += 1 }
        }
        try? writeJournal()
        return failures
    }

    func recoverPreviousSession() -> Int {
        guard trusted, let data = try? Data(contentsOf: journalURL),
              let entries = try? JSONDecoder().decode([RecoveryEntry].self, from: data) else { return 0 }
        let pending: [RecoveryEntry] = ax.sync {
            entries.filter { entry in
                guard let app = NSRunningApplication(processIdentifier: entry.pid), app.bundleIdentifier == entry.bundleID else { return false }
                let application = AXUIElementCreateApplication(entry.pid)
                guard let elements: [AXUIElement] = AX.attribute(application, kAXWindowsAttribute) else { return true }
                // Only recover the same live app process. Never launch or close applications.
                let matches = elements.filter { element in
                    if let number = entry.windowNumber { return AX.windowNumber(element) == number }
                    return (AX.attribute(element, kAXTitleAttribute) as String?) == entry.title
                }
                return matches.contains { !AX.setMinimized($0, false) }
            }
        }
        if let data = try? JSONEncoder().encode(pending) { try? data.write(to: journalURL, options: .atomic) }
        return pending.count
    }

    private func writeJournal() throws {
        let entries = windows.filter(\.minimizedByTatami).map {
            RecoveryEntry(pid: $0.pid, bundleID: $0.bundleID, title: $0.title, frame: Rect($0.frame), windowNumber: $0.windowNumber)
        }
        try JSONEncoder().encode(entries).write(to: journalURL, options: .atomic)
    }

    // MARK: writes

    @discardableResult func move(_ id: UUID, to frame: CGRect) -> Bool {
        guard let index = windows.firstIndex(where: { $0.id == id }), trusted else { return false }
        let element = windows[index].element
        let (moved, actual) = ax.sync { (AX.setFrame(element, frame), AX.frame(of: element)) }
        if let actual { windows[index].frame = actual }
        return moved
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

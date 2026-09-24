import AppKit
import ApplicationServices
import TatamiCore

struct LiveWindow: Identifiable {
    let id: UUID
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String
    let appName: String
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
}

@MainActor final class WindowService {
    var windows: [LiveWindow] = []
    var displays: [DisplayInfo] = []
    private let journalURL: URL

    init(directory: URL) { journalURL = directory.appendingPathComponent("recovery.json"); updateDisplays() }
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

    func scan(state: WorkspaceState) {
        guard trusted else { return }
        var found: [LiveWindow] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.2)
            guard let elements: [AXUIElement] = attribute(application, kAXWindowsAttribute) else { continue }
            for element in elements {
                let role: String? = attribute(element, kAXSubroleAttribute)
                guard role == kAXStandardWindowSubrole as String,
                      let frame = frame(of: element), frame.width > 80, frame.height > 60 else { continue }
                let title: String = attribute(element, kAXTitleAttribute) ?? "Untitled window"
                let minimized: Bool = attribute(element, kAXMinimizedAttribute) ?? false
                let bundleID = app.bundleIdentifier ?? "pid.\(app.processIdentifier)"
                if var existing = windows.first(where: { CFEqual($0.element, element) }) {
                    existing.title = title
                    if !existing.minimizedByTatami { existing.frame = frame }
                    existing.minimized = minimized
                    // Unminimizing from the Dock is an explicit escape hatch.
                    if existing.minimizedByTatami && !minimized { existing.minimizedByTatami = false; existing.stageID = state.activeStageID }
                    if state.excludedBundleIDs.contains(bundleID), existing.minimizedByTatami {
                        _ = setMinimized(false, element: element); existing.minimizedByTatami = false
                    }
                    found.append(existing)
                } else {
                    found.append(LiveWindow(id: UUID(), element: element, pid: app.processIdentifier, bundleID: bundleID,
                                            appName: app.localizedName ?? "Application", title: title, frame: frame, minimized: minimized,
                                            stageID: state.destination(bundleID: bundleID, title: title) ?? state.activeStageID))
                }
            }
        }
        windows = found
    }

    func display(for frame: CGRect) -> DisplayInfo? {
        displays.max { a, b in
            let ar = a.fullFrame.intersection(frame), br = b.fullFrame.intersection(frame)
            return (ar.isNull ? 0 : ar.width * ar.height) < (br.isNull ? 0 : br.width * br.height)
        }
    }

    func applyVisibility(state: WorkspaceState) -> Int {
        guard trusted else { return windows.filter(\.minimizedByTatami).count }
        var failures = 0
        for i in windows.indices {
            let excluded = state.excludedBundleIDs.contains(windows[i].bundleID)
            let visible = excluded || windows[i].stageID == state.activeStageID
            if visible && windows[i].minimizedByTatami {
                if setMinimized(false, element: windows[i].element) {
                    windows[i].minimizedByTatami = false; windows[i].minimized = false
                } else { failures += 1 }
            } else if !visible && !windows[i].minimized && !windows[i].minimizedByTatami {
                // Journal before changing a window. A crash still leaves native Dock recovery available.
                windows[i].minimizedByTatami = true
                do { try writeJournal() } catch { windows[i].minimizedByTatami = false; failures += 1; continue }
                if setMinimized(true, element: windows[i].element) { windows[i].minimized = true }
                else { windows[i].minimizedByTatami = false; failures += 1 }
            }
        }
        try? writeJournal()
        return failures
    }

    func restoreOwnedWindows() -> Int {
        var failures = 0
        for i in windows.indices where windows[i].minimizedByTatami {
            if setMinimized(false, element: windows[i].element) {
                windows[i].minimizedByTatami = false; windows[i].minimized = false
            } else { failures += 1 }
        }
        try? writeJournal()
        return failures
    }

    func recoverPreviousSession() -> Int {
        guard trusted, let data = try? Data(contentsOf: journalURL),
              let entries = try? JSONDecoder().decode([RecoveryEntry].self, from: data) else { return 0 }
        var pending: [RecoveryEntry] = []
        for entry in entries {
            guard let app = NSRunningApplication(processIdentifier: entry.pid), app.bundleIdentifier == entry.bundleID else { continue }
            let application = AXUIElementCreateApplication(entry.pid)
            AXUIElementSetMessagingTimeout(application, 0.2)
            guard let elements: [AXUIElement] = attribute(application, kAXWindowsAttribute) else { pending.append(entry); continue }
            let matches = elements.filter { (attribute($0, kAXTitleAttribute) as String?) == entry.title }
            // Only recover the same live app process and title. Never launch or close applications.
            for element in matches { if !setMinimized(false, element: element) { pending.append(entry) } }
        }
        if let data = try? JSONEncoder().encode(pending) { try? data.write(to: journalURL, options: .atomic) }
        return pending.count
    }

    private func writeJournal() throws {
        let entries = windows.filter(\.minimizedByTatami).map { RecoveryEntry(pid: $0.pid, bundleID: $0.bundleID, title: $0.title, frame: Rect($0.frame)) }
        try JSONEncoder().encode(entries).write(to: journalURL, options: .atomic)
    }

    @discardableResult func move(_ id: UUID, to frame: CGRect) -> Bool {
        guard let index = windows.firstIndex(where: { $0.id == id }), trusted else { return false }
        let element = windows[index].element
        var point = frame.origin, size = frame.size
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return false }
        let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, dimensions)
        let positionResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        if let actual = self.frame(of: element) { windows[index].frame = actual }
        return sizeResult == .success && positionResult == .success
    }

    func focusedID() -> UUID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused: AXUIElement = attribute(application, kAXFocusedWindowAttribute) else { return nil }
        return windows.first(where: { CFEqual($0.element, focused) })?.id
    }

    func focus(_ id: UUID) {
        guard let window = windows.first(where: { $0.id == id }) else { return }
        _ = setMinimized(false, element: window.element)
        NSRunningApplication(processIdentifier: window.pid)?.activate()
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(element, kAXPositionAttribute),
              let size: AXValue = attribute(element, kAXSizeAttribute),
              AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
    private func setMinimized(_ minimized: Bool, element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, minimized ? kCFBooleanTrue : kCFBooleanFalse) == .success
    }
}

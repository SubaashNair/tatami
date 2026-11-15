import AppKit
import ApplicationServices

/// Owns every Accessibility call and observer (M1 decision 2). AX calls block until the target app
/// answers or times out, so none of them may run on the main thread.
final class AXThread: Thread {
    private var runLoop: CFRunLoop!
    private let ready = DispatchSemaphore(value: 0)

    override init() {
        super.init()
        name = "Tatami Accessibility"
        qualityOfService = .userInteractive
        start()
        ready.wait()
    }

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        RunLoop.current.add(NSMachPort(), forMode: .default)  // keeps the run loop alive with no observers yet
        ready.signal()
        while true { autoreleasepool { _ = RunLoop.current.run(mode: .default, before: .distantFuture) } }
    }

    func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    func run<T>(_ block: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in perform { continuation.resume(returning: block()) } }
    }

    // ponytail: writes (moves, minimize, focus) block the caller until done. They are user-initiated and bounded by
    // the global AX timeout; the periodic scan, the old freeze source, is async. Make writes async if switches stutter.
    func sync<T>(_ block: () -> T) -> T {
        if Thread.current === self { return block() }
        return withoutActuallyEscaping(block) { block in
            // The run loop may keep its copy of the performed block alive after it ran, so that block must not
            // capture `block` (that traps "non-escaping closure has escaped"). The job drops it before signalling.
            let job = SyncJob(block)
            perform { job.run() }
            job.done.wait()
            return job.result!
        }
    }

    private final class SyncJob<T> {
        private var work: (() -> T)?
        private(set) var result: T?
        let done = DispatchSemaphore(value: 0)
        init(_ work: @escaping () -> T) { self.work = work }
        func run() {
            result = work?()
            work = nil
            done.signal()
        }
    }

    func add(_ source: CFRunLoopSource) { CFRunLoopAddSource(runLoop, source, .defaultMode) }
    func remove(_ source: CFRunLoopSource) { CFRunLoopRemoveSource(runLoop, source, .defaultMode) }
}

/// Stateless AX helpers. Call only on the AX thread.
enum AX {
    /// One hung app must not stall everything: cap every AX message.
    static func configureGlobalTimeout() { AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25) }

    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Like `attribute`, but also says whether the app failed to answer in time (as opposed to the attribute not existing).
    static func attributeOrTimeout<T>(_ element: AXUIElement, _ name: String) -> (value: T?, timedOut: Bool) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return (status == .success ? value as? T : nil, status == .cannotComplete)
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(element, kAXPositionAttribute),
              let size: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    @discardableResult static func setFrame(_ element: AXUIElement, _ frame: CGRect) -> Bool {
        var point = frame.origin, size = frame.size
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return false }
        // Size, position, size: some apps clamp size against the old position.
        let first = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, dimensions)
        let moved = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        let second = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, dimensions)
        return moved == .success && (first == .success || second == .success)
    }

    @discardableResult static func setPosition(_ element: AXUIElement, _ origin: CGPoint) -> Bool {
        var point = origin
        guard let position = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position) == .success
    }

    /// Chrome, Firefox, and Electron animate every resize while this is on, which makes parking visibly slow.
    /// Assistive tools rely on it, so turn it off only around our moves and restore it (M1 decision 6).
    static func withoutEnhancedUI<T>(pid: pid_t, _ body: () -> T) -> T {
        let app = AXUIElementCreateApplication(pid)
        let key = "AXEnhancedUserInterface" as CFString
        var value: CFTypeRef?
        let wasOn = AXUIElementCopyAttributeValue(app, key, &value) == .success && (value as? Bool) == true
        if wasOn { AXUIElementSetAttributeValue(app, key, kCFBooleanFalse) }
        defer { if wasOn { AXUIElementSetAttributeValue(app, key, kCFBooleanTrue) } }
        return body()
    }

    static func setMinimized(_ element: AXUIElement, _ minimized: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, minimized ? kCFBooleanTrue : kCFBooleanFalse) == .success
    }

    // Private but stable for a decade and used by Rectangle, AeroSpace, and yabai (M1 decision 5).
    // Looked up at runtime so a future macOS without it degrades to title matching instead of failing to launch.
    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindow: GetWindowFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }  // RTLD_DEFAULT
        return unsafeBitCast(symbol, to: GetWindowFunction.self)
    }()

    static func windowNumber(_ element: AXUIElement) -> UInt32? {
        var id = CGWindowID(0)
        guard let getWindow, getWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }
}

struct AppInfo {
    let pid: pid_t
    let bundleID: String
    let name: String
}

struct ScannedWindow {
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String
    let appName: String
    let windowNumber: UInt32?
    let title: String
    let frame: CGRect
    let minimized: Bool
    /// In macOS full screen (its own Space), which is not a tile to place and not a window to float.
    var fullscreen = false
}

struct ScanResult {
    var windows: [ScannedWindow] = []
    /// Apps that did not answer in time. Their windows are unknown, which is different from having none.
    var failed: Set<pid_t> = []
}

enum AXScanner {
    /// Standard windows of the given apps. AX thread only.
    static func scan(_ apps: [AppInfo]) -> ScanResult {
        var result = ScanResult()
        for app in apps {
            let application = AXUIElementCreateApplication(app.pid)
            let listed: (value: [AXUIElement]?, timedOut: Bool) = AX.attributeOrTimeout(application, kAXWindowsAttribute)
            if listed.timedOut { result.failed.insert(app.pid) }
            for element in listed.value ?? [] {
                let subrole: (value: String?, timedOut: Bool) = AX.attributeOrTimeout(element, kAXSubroleAttribute)
                guard !subrole.timedOut, let frame = AX.frame(of: element) else { result.failed.insert(app.pid); continue }
                guard subrole.value == kAXStandardWindowSubrole as String, frame.width > 80, frame.height > 60 else { continue }
                result.windows.append(ScannedWindow(element: element, pid: app.pid, bundleID: app.bundleID, appName: app.name,
                                                    windowNumber: AX.windowNumber(element), title: AX.attribute(element, kAXTitleAttribute) ?? "Untitled window",
                                                    frame: frame, minimized: AX.attribute(element, kAXMinimizedAttribute) ?? false,
                                                    fullscreen: AX.attribute(element, "AXFullScreen") ?? false))
            }
        }
        return result
    }
}

/// Per-app AXObservers, created and fired on the AX thread. Events are forwarded to the main thread.
final class AXObservers {
    private let thread: AXThread
    private var observers: [pid_t: AXObserver] = [:]
    private var watchedWindows: [pid_t: Set<UInt32>] = [:]
    private let onEvent: (pid_t, String) -> Void

    static let appNotifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                                   kAXWindowMovedNotification, kAXWindowResizedNotification, kAXWindowMiniaturizedNotification,
                                   kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification]

    init(thread: AXThread, onEvent: @escaping (pid_t, String) -> Void) {
        self.thread = thread; self.onEvent = onEvent
    }

    /// AX thread only. Adds observers for new apps and drops those for quit apps.
    func sync(pids: Set<pid_t>) {
        for (pid, observer) in observers where !pids.contains(pid) {
            thread.remove(AXObserverGetRunLoopSource(observer))
            observers[pid] = nil; watchedWindows[pid] = nil
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for pid in pids where observers[pid] == nil {
            var observer: AXObserver?
            guard AXObserverCreate(pid, axObserverCallback, &observer) == .success, let observer else { continue }
            let application = AXUIElementCreateApplication(pid)
            for name in Self.appNotifications { AXObserverAddNotification(observer, application, name as CFString, refcon) }
            thread.add(AXObserverGetRunLoopSource(observer))
            observers[pid] = observer
        }
    }

    /// AX thread only. Destroyed notifications must be registered per window.
    func watch(_ windows: [ScannedWindow]) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for window in windows {
            guard let observer = observers[window.pid], let number = window.windowNumber,
                  watchedWindows[window.pid, default: []].insert(number).inserted else { continue }
            AXObserverAddNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString, refcon)
        }
    }

    fileprivate func fire(pid: pid_t, notification: String) {
        let onEvent = onEvent
        DispatchQueue.main.async { onEvent(pid, notification) }
    }
}

private func axObserverCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    Unmanaged<AXObservers>.fromOpaque(refcon).takeUnretainedValue().fire(pid: pid, notification: notification as String)
}

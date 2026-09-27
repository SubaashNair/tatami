import AppKit
import TatamiCore

/// Modifier + scroll switches Stages (M2 decision 5). The event tap swallows only scrolls with exactly the
/// preset's modifiers, so ordinary scrolling and other modifier-scroll shortcuts are untouched.
@MainActor final class ScrollSwitcher {
    var onSwitch: ((Int) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var required: CGEventFlags = []
    // Trackpads send many small continuous deltas; mouse wheels send one event per notch.
    private var trackpad = ScrollAccumulator(threshold: 40, cooldown: 0.45)
    private var wheel = ScrollAccumulator(threshold: 0.1, cooldown: 0.12)
    private static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]

    /// False when macOS refused the event tap, so the caller can say scroll switching is unavailable.
    @discardableResult func start(preset: ShortcutPreset) -> Bool {
        required = preset == .classic ? [.maskAlternate] : [.maskControl, .maskAlternate]
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                          callback: scrollTapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap; self.source = source
        return true
    }

    func stop() {
        guard let tap, let source else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = nil; self.source = nil
    }

    /// Returns true when the event should be swallowed.
    fileprivate func handle(_ event: CGEvent) -> Bool {
        guard event.flags.intersection(Self.modifierMask) == required else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        let offset: Int
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
            offset = trackpad.add(delta: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), at: now)
        } else {
            offset = wheel.add(delta: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)), at: now)
        }
        if offset != 0 { onSwitch?(offset) }
        return true
    }

    fileprivate func reenable() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }
}

private func scrollTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let switcher = Unmanaged<ScrollSwitcher>.fromOpaque(refcon).takeUnretainedValue()
    // macOS disables slow taps; turn it back on rather than silently losing the feature.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { switcher.reenable() }
        return Unmanaged.passUnretained(event)
    }
    let swallow = MainActor.assumeIsolated { switcher.handle(event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

import AppKit
import Carbon
import TatamiCore

enum HotkeyAction {
    case backRoom, sendRoom(Int), stage(Int), send(Int), cycle(Int), snap(SnapZone), stagesBar, retile, rescue, organizer, newStage, closeStage, mergeAll, cycleAppWindows(Int), cycleMode, focusPane(Direction), moveToPane(Direction), tab(Int), zoomPane, splitPane(Axis), resizePane(Double), reflow, undoLayout, raiseFloats, sendToDisplay(Int), cycleWindows(Int), focusPaneNumber(Int), movePaneNumber(Int), rotateSplit, toggleFloat, toggleFloatApp
}

@MainActor final class Hotkeys {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32: HotkeyAction] = [:]
    var onAction: ((HotkeyAction) -> Void)?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context -> OSStatus in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let manager = Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if let action = manager.actions[id.id] { manager.onAction?(action) }
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func unregister() { refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll(); actions.removeAll() }

    func register(preset: ShortcutPreset, scopeCommandBacktick: Bool = false) -> Int {
        unregister()
        var failures = 0
        let classic = preset == .classic
        let base = UInt32(optionKey | (classic ? 0 : controlKey))
        // Plain Option+arrows is word/paragraph navigation; standard moves navigation to Control+Option+Command.
        let navigation = UInt32(optionKey | (classic ? 0 : controlKey | cmdKey))
        let numbers = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        func bind(_ code: Int, _ modifiers: UInt32, _ action: HotkeyAction) {
            let number = UInt32(actions.count + 1)
            actions[number] = action
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(code), modifiers, EventHotKeyID(signature: 0x54415441, id: number), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) } else { failures += 1 }
        }
        for (i, code) in numbers.enumerated() { bind(code, base, .stage(i)); bind(code, base | UInt32(shiftKey), .send(i)) }
        bind(kVK_LeftArrow, navigation, .cycle(-1))
        bind(kVK_RightArrow, navigation, .cycle(1))
        bind(kVK_UpArrow, navigation, .stagesBar)
        bind(kVK_DownArrow, navigation, .retile)
        bind(kVK_ANSI_R, UInt32(controlKey | optionKey | cmdKey), .rescue)
        bind(kVK_Tab, base, .cycle(1))
        bind(kVK_Tab, base | UInt32(shiftKey), .cycle(-1))
        bind(kVK_ANSI_Grave, base, .backRoom)  // previous Room, like AeroSpace's workspace-back-and-forth
        bind(kVK_ANSI_N, base, .newStage)
        bind(kVK_ANSI_X, base, .closeStage)
        bind(kVK_ANSI_M, base, .mergeAll)
        bind(kVK_ANSI_B, base, .cycleMode)
        // Tiles (M3 decision 5). ⌃⌥⌘\ splits right; with Shift, below (⌃⌥⌘− is shrink).
        let pane = UInt32(cmdKey | optionKey | (classic ? 0 : controlKey))
        bind(kVK_Tab, pane, .sendRoom(1))  // send this display's Room to the next display, like AeroSpace's move-workspace-to-monitor
        bind(kVK_Tab, pane | UInt32(shiftKey), .sendRoom(-1))
        for (code, direction) in [(kVK_ANSI_I, Direction.up), (kVK_ANSI_J, .left), (kVK_ANSI_K, .down), (kVK_ANSI_L, .right)] {
            bind(code, pane, .focusPane(direction))
            bind(code, pane | UInt32(shiftKey), .moveToPane(direction))
        }
        bind(kVK_ANSI_LeftBracket, UInt32(controlKey | optionKey), .tab(-1))
        bind(kVK_ANSI_RightBracket, UInt32(controlKey | optionKey), .tab(1))
        bind(kVK_Return, pane, .zoomPane)
        bind(kVK_ANSI_Backslash, pane, .splitPane(.horizontal))
        bind(kVK_ANSI_Backslash, pane | UInt32(shiftKey), .splitPane(.vertical))
        bind(kVK_ANSI_Equal, pane, .resizePane(0.05))
        bind(kVK_ANSI_Minus, pane, .resizePane(-0.05))
        bind(kVK_ANSI_G, pane, .reflow)
        bind(kVK_ANSI_Z, pane, .undoLayout)
        bind(kVK_ANSI_F, pane, .raiseFloats)
        // Panes are numbered 1, 2, 3… in reading order (shown on each tab bar): go to one, or send the window there.
        for (i, code) in numbers.enumerated() { bind(code, pane, .focusPaneNumber(i + 1)); bind(code, pane | UInt32(shiftKey), .movePaneNumber(i + 1)) }
        bind(kVK_ANSI_Slash, pane, .rotateSplit)
        bind(kVK_ANSI_T, pane, .toggleFloat)  // float or tile the focused window; add Shift for the whole app
        bind(kVK_ANSI_T, pane | UInt32(shiftKey), .toggleFloatApp)
        bind(kVK_ANSI_LeftBracket, pane, .cycleWindows(-1))
        bind(kVK_ANSI_RightBracket, pane, .cycleWindows(1))
        bind(kVK_ANSI_LeftBracket, pane | UInt32(shiftKey), .sendToDisplay(-1))
        bind(kVK_ANSI_RightBracket, pane | UInt32(shiftKey), .sendToDisplay(1))
        if scopeCommandBacktick {
            bind(kVK_ANSI_Grave, UInt32(cmdKey), .cycleAppWindows(1))
            bind(kVK_ANSI_Grave, UInt32(cmdKey | shiftKey), .cycleAppWindows(-1))
        }
        let zones: [(Int, SnapZone)] = [(kVK_LeftArrow, .left), (kVK_RightArrow, .right), (kVK_UpArrow, .top), (kVK_DownArrow, .bottom),
            (kVK_ANSI_U, .topLeft), (kVK_ANSI_I, .topRight), (kVK_ANSI_J, .bottomLeft), (kVK_ANSI_K, .bottomRight),
            (kVK_ANSI_A, .leftThird), (kVK_ANSI_S, .centerThird), (kVK_ANSI_D, .rightThird),
            (kVK_ANSI_Q, .leftTwoThirds), (kVK_ANSI_R, .centerTwoThirds), (kVK_ANSI_W, .rightTwoThirds), (kVK_ANSI_C, .center), (kVK_Return, .maximize)]
        for (key, zone) in zones { bind(key, UInt32(controlKey | optionKey), .snap(zone)) }
        // ponytail: same combo in both presets; Control+Option+Z types nothing, so Classic needs no variant.
        bind(kVK_ANSI_Z, UInt32(controlKey | optionKey), .organizer)
        return failures
    }
}

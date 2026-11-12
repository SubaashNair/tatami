import Carbon
import CoreGraphics

/// Posts ⌘N to the frontmost app, by the key that types "n" on the current keyboard layout (not the physical QWERTY position,
/// which is another letter on Dvorak or Colemak), from a private event source so a held Shift or Option cannot join in.
enum KeyPress {
    static func commandN() {
        let source = CGEventSource(stateID: .privateState)
        let code = keyCode(producing: "n") ?? 0x2D
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// The key code that types `character` with no modifiers on the current layout.
    static func keyCode(producing character: Character) -> CGKeyCode? {
        guard let input = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(input, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = unsafeBitCast(raw, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layout) else { return nil }
        let keyLayout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        for code in 0..<128 {
            var dead: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(keyLayout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
            if status == noErr, length == 1, let scalar = Unicode.Scalar(chars[0]), Character(scalar) == character { return CGKeyCode(code) }
        }
        return nil
    }
}

import AppKit
import Carbon.HIToolbox

/// A key plus its modifiers, as chosen by the user and stored in preferences.
///
/// The `keyCode` is a *physical* key position, not a character. That is what
/// Carbon registers against, and it is the right thing to store: a shortcut
/// pinned to a position keeps working when the user switches keyboard layout.
/// Turning it back into a label the user recognises is `displayString`'s job,
/// and that part is layout-dependent.
struct KeyCombo: Equatable, Hashable, Codable, Sendable {
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags` is not `Codable`, so the raw value is persisted.
    private var modifierRawValue: UInt

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        // Keep only the four modifiers Carbon can register. Device-dependent
        // bits (which physical shift key was pressed, caps lock, fn) would
        // otherwise make two visually identical combos compare as different.
        self.modifierRawValue = modifiers.intersection([.command, .option, .control, .shift]).rawValue
    }

    /// Control-Option-Command-P: deliberately awkward, because the cost of
    /// triggering this by accident mid-presentation is higher than the cost of
    /// a four-finger chord.
    static let `default` = KeyCombo(keyCode: UInt16(kVK_ANSI_P), modifiers: [.control, .option, .command])

    /// Carbon uses its own modifier constants, unrelated to AppKit's bit layout.
    var carbonModifiers: UInt32 {
        var result: Int = 0
        if modifiers.contains(.command) { result |= cmdKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    /// A shortcut with no modifier — or with only Shift — would swallow ordinary
    /// typing system-wide, so the recorder refuses to accept one.
    var isValid: Bool {
        !modifiers.intersection([.command, .option, .control]).isEmpty
    }

    /// Rendered the way macOS renders shortcuts: modifiers in the canonical
    /// ⌃⌥⇧⌘ order, then the key.
    var displayString: String {
        Self.displayString(for: modifiers) + KeyCodeNaming.label(for: keyCode)
    }

    /// Just the modifier symbols. The recorder needs these on their own, to show
    /// the chord building up while no key has been pressed yet.
    static func displayString(for modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }
}

/// Turns a physical key code into something a human recognises.
enum KeyCodeNaming {
    /// Keys with no printable character, or whose symbol is conventional rather
    /// than whatever the layout would produce.
    private static let specialKeys: [UInt16: String] = [
        UInt16(kVK_Return): "↩",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_Escape): "⎋",
        UInt16(kVK_Home): "↖",
        UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞",
        UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_ANSI_KeypadEnter): "⌤",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]

    static func label(for keyCode: UInt16) -> String {
        if let special = specialKeys[keyCode] { return special }
        if let character = printableCharacter(for: keyCode) { return character }
        return "Key \(keyCode)"
    }

    /// Asks the *current keyboard layout* what character this physical key
    /// produces, so a French user configuring the key where QWERTY has `A`
    /// sees `Q` — which is what is actually printed on their keyboard.
    private static func printableCharacter(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,                                    // no modifiers: we want the bare key
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

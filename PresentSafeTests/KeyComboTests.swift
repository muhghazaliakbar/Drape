import AppKit
import Carbon.HIToolbox
import Testing

@testable import PresentSafe

@Suite("KeyCombo")
struct KeyComboTests {

    // MARK: - Carbon translation

    @Test("Each AppKit modifier maps to its Carbon counterpart")
    func carbonModifiersMapIndividually() {
        #expect(KeyCombo(keyCode: 0, modifiers: .command).carbonModifiers == UInt32(cmdKey))
        #expect(KeyCombo(keyCode: 0, modifiers: .option).carbonModifiers == UInt32(optionKey))
        #expect(KeyCombo(keyCode: 0, modifiers: .control).carbonModifiers == UInt32(controlKey))
        #expect(KeyCombo(keyCode: 0, modifiers: .shift).carbonModifiers == UInt32(shiftKey))
    }

    @Test("Combined modifiers are OR-ed together")
    func carbonModifiersCombine() {
        let combo = KeyCombo(keyCode: 0, modifiers: [.control, .option, .command])
        #expect(combo.carbonModifiers == UInt32(controlKey | optionKey | cmdKey))
    }

    @Test("No modifiers means no Carbon bits")
    func carbonModifiersEmpty() {
        #expect(KeyCombo(keyCode: 0, modifiers: []).carbonModifiers == 0)
    }

    // MARK: - Normalisation

    @Test("Modifiers Carbon cannot register are discarded")
    func stripsUnsupportedModifiers() {
        // Caps Lock and Fn are real `NSEvent.ModifierFlags` values that
        // `RegisterEventHotKey` has no concept of. Left in place they would make
        // two identical shortcuts compare as different.
        let withNoise = KeyCombo(keyCode: 12, modifiers: [.command, .capsLock, .function])
        let clean = KeyCombo(keyCode: 12, modifiers: [.command])
        #expect(withNoise == clean)
        #expect(withNoise.modifiers == .command)
    }

    @Test("Equal combos hash equally")
    func hashingFollowsEquality() {
        let a = KeyCombo(keyCode: 3, modifiers: [.command, .shift, .capsLock])
        let b = KeyCombo(keyCode: 3, modifiers: [.shift, .command])
        #expect(a.hashValue == b.hashValue)
    }

    // MARK: - Validity

    @Test("A shortcut needs a real modifier")
    func rejectsModifierlessCombos() {
        #expect(KeyCombo(keyCode: 0, modifiers: []).isValid == false)
    }

    @Test("Shift alone is not enough")
    func rejectsShiftOnly() {
        // ⇧A is just a capital A: registering it would swallow typing everywhere.
        #expect(KeyCombo(keyCode: 0, modifiers: .shift).isValid == false)
    }

    @Test("Command, Option or Control each qualify", arguments: [
        NSEvent.ModifierFlags.command, .option, .control,
    ])
    func acceptsRealModifiers(modifier: NSEvent.ModifierFlags) {
        #expect(KeyCombo(keyCode: 0, modifiers: modifier).isValid)
    }

    // MARK: - System shortcut protection

    @Test("Bare Command shortcuts that would strand the user are flagged", arguments: [
        (kVK_ANSI_Q, "Quit"),
        (kVK_ANSI_W, "Close Window"),
        (kVK_Tab, "Switch Apps"),
        (kVK_Space, "Spotlight"),
    ])
    func flagsSystemCriticalShortcuts(keyCode: Int, expected: String) {
        let combo = KeyCombo(keyCode: UInt16(keyCode), modifiers: .command)
        #expect(combo.shadowedSystemShortcut == expected)
    }

    @Test("Adding another modifier makes it safe again")
    func extraModifierClearsTheConflict() {
        // ⌘Q is Quit; ⌥⌘Q is not, so there is nothing to protect.
        #expect(KeyCombo(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command, .option]).shadowedSystemShortcut == nil)
        #expect(KeyCombo(keyCode: UInt16(kVK_ANSI_Q), modifiers: .option).shadowedSystemShortcut == nil)
    }

    @Test("Ordinary shortcuts are left alone")
    func leavesHarmlessShortcutsAlone() {
        #expect(KeyCombo(keyCode: UInt16(kVK_ANSI_P), modifiers: .command).shadowedSystemShortcut == nil)
    }

    @Test("The shipped default is usable")
    func defaultComboIsSane() {
        #expect(KeyCombo.default.isValid)
        #expect(KeyCombo.default.shadowedSystemShortcut == nil)
    }

    // MARK: - Display

    @Test("Modifier symbols follow the order macOS uses")
    func modifierSymbolsAreOrdered() {
        let all = KeyCombo.displayString(for: [.command, .shift, .option, .control])
        #expect(all == "⌃⌥⇧⌘")
    }

    @Test("No modifiers renders as nothing")
    func emptyModifiersRenderEmpty() {
        #expect(KeyCombo.displayString(for: []).isEmpty)
    }

    @Test("A combo renders its modifiers followed by its key")
    @MainActor
    func displayStringIsModifiersThenKey() {
        let combo = KeyCombo(keyCode: UInt16(kVK_Space), modifiers: [.control, .command])
        #expect(combo.displayString == "⌃⌘Space")
    }

    // MARK: - Persistence

    @Test("Survives a Codable round trip")
    func codableRoundTrip() throws {
        let original = KeyCombo(keyCode: 42, modifiers: [.control, .shift])
        let decoded = try JSONDecoder().decode(
            KeyCombo.self,
            from: try JSONEncoder().encode(original)
        )
        #expect(decoded == original)
        #expect(decoded.keyCode == 42)
        #expect(decoded.modifiers == [.control, .shift])
    }
}

@Suite("KeyCodeNaming")
struct KeyCodeNamingTests {

    @Test("Named keys use their conventional symbol", arguments: [
        (kVK_Return, "↩"),
        (kVK_Escape, "⎋"),
        (kVK_Space, "Space"),
        (kVK_Delete, "⌫"),
        (kVK_LeftArrow, "←"),
        (kVK_F5, "F5"),
    ])
    func specialKeysHaveSymbols(keyCode: Int, expected: String) {
        #expect(KeyCodeNaming.label(for: UInt16(keyCode)) == expected)
    }

    @Test("Printable keys resolve through the active keyboard layout")
    @MainActor
    func printableKeysResolveToCharacters() {
        // The character depends on the user's layout, so this asserts the shape
        // of the answer rather than a specific letter: a single uppercase
        // character, never the "Key 35" fallback.
        let label = KeyCodeNaming.label(for: UInt16(kVK_ANSI_P))
        #expect(label.count == 1)
        #expect(label == label.uppercased())
        #expect(!label.hasPrefix("Key "))
    }

    @Test("An unmapped key code still produces something printable")
    func unknownKeyCodeFallsBack() {
        let label = KeyCodeNaming.label(for: 9999)
        #expect(!label.isEmpty)
    }
}

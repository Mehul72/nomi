import AppKit
import Carbon.HIToolbox

/// A key plus modifiers, stored by virtual key code so it survives keyboard layout changes.
nonisolated struct KeyboardShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt16
    /// Raw `NSEvent.ModifierFlags`, limited to the device-independent mask.
    var modifierFlags: UInt

    static let optionSpace = KeyboardShortcut(keyCode: UInt16(kVK_Space), modifierFlags: NSEvent.ModifierFlags.option.rawValue)

    init(keyCode: UInt16, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.init(keyCode: keyCode, modifierFlags: modifiers.rawValue)
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    /// True when the combination could act as a global shortcut: at least one modifier and a real key.
    var isUsableGlobally: Bool {
        !modifiers.intersection([.command, .option, .control, .shift]).isEmpty && !Self.isModifierKey(keyCode)
    }

    /// Modifier bits in the form Carbon's `RegisterEventHotKey` expects.
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyLabel(for: keyCode))
        return parts.joined()
    }

    static func isModifierKey(_ keyCode: UInt16) -> Bool {
        [kVK_Command, kVK_RightCommand, kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
         kVK_Shift, kVK_RightShift, kVK_CapsLock, kVK_Function].contains(Int(keyCode))
    }

    static func keyLabel(for keyCode: UInt16) -> String {
        if let special = specialKeyLabels[Int(keyCode)] { return special }
        return printableLabel(for: keyCode) ?? "Key \(keyCode)"
    }

    private static let specialKeyLabels: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_Help: "?⃝",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_ANSI_KeypadEnter: "⌤", kVK_ANSI_KeypadClear: "⌧",
    ]

    /// Asks the current keyboard layout what the key prints with no modifiers held.
    private static func printableLabel(for keyCode: UInt16) -> String? {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { bytes -> String? in
            guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length).uppercased()
        }
    }
}

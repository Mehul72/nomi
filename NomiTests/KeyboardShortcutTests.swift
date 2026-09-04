import AppKit
import Carbon.HIToolbox
import Testing
@testable import Nomi

struct KeyboardShortcutTests {
    @Test func defaultIsOptionSpace() {
        let shortcut = KeyboardShortcut.optionSpace
        #expect(shortcut.keyCode == UInt16(kVK_Space))
        #expect(shortcut.modifiers == .option)
        #expect(shortcut.displayString == "⌥Space")
        #expect(shortcut.isUsableGlobally)
    }

    @Test func deviceDependentModifierBitsAreDropped() {
        let raw = NSEvent.ModifierFlags.option.rawValue | 0x20  // left-option device bit
        let shortcut = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_N), modifierFlags: raw)
        #expect(shortcut.modifiers == .option)
    }

    @Test func aKeyWithoutModifiersIsNotGlobal() {
        #expect(!KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: []).isUsableGlobally)
        #expect(!KeyboardShortcut(keyCode: UInt16(kVK_Option), modifiers: .option).isUsableGlobally)
        #expect(KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command, .shift]).isUsableGlobally)
    }

    @Test func carbonModifiersMatchAppKitFlags() {
        let shortcut = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .control, .shift, .option])
        #expect(shortcut.carbonModifiers == UInt32(cmdKey | controlKey | shiftKey | optionKey))
    }

    @Test func displayOrderFollowsTheMacConvention() {
        let shortcut = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_N), modifiers: [.command, .control, .shift, .option])
        #expect(shortcut.displayString == "⌃⌥⇧⌘N")
    }

    @Test func roundTripsThroughJSON() throws {
        let original = KeyboardShortcut(keyCode: UInt16(kVK_F5), modifiers: [.control])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: data)
        #expect(decoded == original)
        #expect(decoded.displayString == "⌃F5")
    }
}

struct SystemShortcutConflictsTests {
    /// The shape of `AppleSymbolicHotKeys` as written by System Settings: Spotlight on ⌘Space.
    static let sample: [String: Any] = [
        "64": ["enabled": true, "value": ["parameters": [32, 49, 1_048_576], "type": "standard"]],
        "65": ["enabled": false, "value": ["parameters": [32, 49, 1_572_864], "type": "standard"]],
        "9999": ["enabled": true, "value": ["parameters": [110, 45, 786_432], "type": "standard"]],
    ]

    @Test func reportsAnEnabledSystemShortcutByName() {
        let conflicts = SystemShortcutConflicts(defaults: Self.sample)
        let commandSpace = KeyboardShortcut(keyCode: UInt16(kVK_Space), modifiers: .command)
        #expect(conflicts.conflict(for: commandSpace) == "Spotlight")
    }

    @Test func ignoresDisabledShortcuts() {
        let conflicts = SystemShortcutConflicts(defaults: Self.sample)
        let commandOptionSpace = KeyboardShortcut(keyCode: UInt16(kVK_Space), modifiers: [.command, .option])
        #expect(conflicts.conflict(for: commandOptionSpace) == nil)
    }

    @Test func unknownIdentifiersStillCountAsConflicts() {
        let conflicts = SystemShortcutConflicts(defaults: Self.sample)
        let controlOptionN = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_N), modifiers: [.control, .option])
        #expect(conflicts.conflict(for: controlOptionN) == "a macOS keyboard shortcut")
    }

    @Test func optionSpaceIsFreeInTheSample() {
        let conflicts = SystemShortcutConflicts(defaults: Self.sample)
        #expect(conflicts.conflict(for: .optionSpace) == nil)
    }

    @Test func missingPreferencesMeanNoConflicts() {
        let conflicts = SystemShortcutConflicts(defaults: nil)
        #expect(conflicts.conflict(for: .optionSpace) == nil)
    }
}

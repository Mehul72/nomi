import AppKit

/// Looks up whether macOS already uses a shortcut, from the same preferences the Keyboard settings pane writes.
nonisolated struct SystemShortcutConflicts {
    private let hotKeys: [String: Any]

    init(defaults: [String: Any]? = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")) {
        hotKeys = defaults ?? [:]
    }

    /// A short description of the system feature bound to the shortcut, or nil when it is free.
    func conflict(for shortcut: KeyboardShortcut) -> String? {
        for (idString, entry) in hotKeys {
            guard
                let entry = entry as? [String: Any],
                (entry["enabled"] as? Bool) ?? true,
                let value = entry["value"] as? [String: Any],
                let parameters = value["parameters"] as? [Int], parameters.count >= 3
            else { continue }
            let keyCode = parameters[1]
            let flags = UInt(parameters[2]) & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
            if keyCode == Int(shortcut.keyCode), flags == shortcut.modifierFlags {
                return Self.featureNames[Int(idString) ?? -1] ?? "a macOS keyboard shortcut"
            }
        }
        return nil
    }

    private static let featureNames: [Int: String] = [
        32: "Mission Control", 33: "Application windows", 36: "Show Desktop", 60: "Select the previous input source",
        61: "Select the next input source", 64: "Spotlight", 65: "Finder search window", 79: "Move left a space",
        81: "Move right a space", 118: "Switch to Desktop 1", 119: "Switch to Desktop 2", 120: "Switch to Desktop 3",
        160: "Launchpad", 163: "Show Notification Center", 175: "Show Launchpad", 184: "Screenshot",
        190: "Look up in Dictionary", 222: "Quick Note",
    ]
}

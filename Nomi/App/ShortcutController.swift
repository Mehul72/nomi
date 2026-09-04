import Foundation
import Observation

/// Keeps the registered global shortcut in step with the preference and reports problems for Settings to show.
@Observable
final class ShortcutController {
    private(set) var problem: String?
    private let preferences: Preferences
    private let registrar: HotKeyRegistrar
    private let conflicts = SystemShortcutConflicts()

    init(preferences: Preferences, onPress: @escaping () -> Void) {
        self.preferences = preferences
        registrar = HotKeyRegistrar(onPress: onPress)
        apply(preferences.shortcut)
    }

    var shortcut: KeyboardShortcut { preferences.shortcut }

    func change(to shortcut: KeyboardShortcut) {
        preferences.shortcut = shortcut
        apply(shortcut)
    }

    private func apply(_ shortcut: KeyboardShortcut) {
        do {
            try registrar.register(shortcut)
        } catch {
            switch error {
            case .notUsableGlobally:
                problem = "Add at least one modifier key, such as Option or Command."
            case .rejected(let status):
                Log.app.error("Hot key registration failed with status \(status)")
                problem = "macOS would not register \(shortcut.displayString). Try a different combination."
            }
            return
        }
        if let feature = conflicts.conflict(for: shortcut) {
            problem = "\(shortcut.displayString) is also used by \(feature). Both will respond until one is changed in System Settings."
        } else {
            problem = nil
        }
    }
}

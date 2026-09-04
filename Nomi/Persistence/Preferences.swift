import Foundation
import Observation

/// User preferences backed by `UserDefaults`. One property per setting, so call sites never touch raw keys.
@Observable
final class Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasClosedNotchOnce = defaults.bool(forKey: Key.hasClosedNotchOnce)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        shortcut = Self.decode(KeyboardShortcut.self, from: defaults, key: Key.shortcut) ?? .optionSpace
        showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
        playsSounds = defaults.object(forKey: Key.playsSounds) as? Bool ?? true
        speaksResponses = defaults.bool(forKey: Key.speaksResponses)
    }

    var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon) }
    }

    var playsSounds: Bool {
        didSet { defaults.set(playsSounds, forKey: Key.playsSounds) }
    }

    var speaksResponses: Bool {
        didSet { defaults.set(speaksResponses, forKey: Key.speaksResponses) }
    }

    var shortcut: KeyboardShortcut {
        didSet { Self.encode(shortcut, into: defaults, key: Key.shortcut) }
    }

    var hasClosedNotchOnce: Bool {
        didSet { defaults.set(hasClosedNotchOnce, forKey: Key.hasClosedNotchOnce) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    private enum Key {
        static let hasClosedNotchOnce = "hasClosedNotchOnce"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let shortcut = "shortcut"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let playsSounds = "playsSounds"
        static let speaksResponses = "speaksResponses"
    }

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Log.app.error("Preference \(key, privacy: .public) is unreadable and will be reset: \(error, privacy: .public)")
            return nil
        }
    }

    private static func encode<T: Encodable>(_ value: T, into defaults: UserDefaults, key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            Log.app.error("Preference \(key, privacy: .public) could not be saved: \(error, privacy: .public)")
        }
    }
}

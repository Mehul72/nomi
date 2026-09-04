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
        selectedModelID = defaults.string(forKey: Key.selectedModelID) ?? ModelCatalog.defaultLanguageModel.id
        generation = Self.decode(GenerationSettings.self, from: defaults, key: Key.generation) ?? GenerationSettings()
        confirmsMediumRisk = defaults.object(forKey: Key.confirmsMediumRisk) as? Bool ?? true
        offlineMode = defaults.bool(forKey: Key.offlineMode)
        homeLocation = defaults.string(forKey: Key.homeLocation)
        disabledToolNames = Set(defaults.stringArray(forKey: Key.disabledToolNames) ?? [])
    }

    var disabledToolNames: Set<String> {
        didSet { defaults.set(Array(disabledToolNames).sorted(), forKey: Key.disabledToolNames) }
    }

    var confirmsMediumRisk: Bool {
        didSet { defaults.set(confirmsMediumRisk, forKey: Key.confirmsMediumRisk) }
    }

    var offlineMode: Bool {
        didSet { defaults.set(offlineMode, forKey: Key.offlineMode) }
    }

    var homeLocation: String? {
        didSet { defaults.set(homeLocation, forKey: Key.homeLocation) }
    }

    var selectedModelID: String {
        didSet { defaults.set(selectedModelID, forKey: Key.selectedModelID) }
    }

    var generation: GenerationSettings {
        didSet { Self.encode(generation, into: defaults, key: Key.generation) }
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
        static let selectedModelID = "selectedModelID"
        static let generation = "generation"
        static let confirmsMediumRisk = "confirmsMediumRisk"
        static let offlineMode = "offlineMode"
        static let homeLocation = "homeLocation"
        static let disabledToolNames = "disabledToolNames"
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

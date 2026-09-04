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
    }
}

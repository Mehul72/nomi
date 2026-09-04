import Observation

/// Which Settings section is showing, so deep links and the window share one selection.
@Observable
final class SettingsNavigation {
    var section: SettingsSection = .general
}

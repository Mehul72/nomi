import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(ShortcutController.self) private var shortcutController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginProblem: String?

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchAtLoginProblem {
                    Text(launchAtLoginProblem).foregroundStyle(.secondary)
                }
                Toggle("Show icon in menu bar", isOn: $preferences.showsMenuBarIcon)
            }
            Section {
                LabeledContent("Open Nomi") {
                    ShortcutRecorderView(shortcut: shortcutController.shortcut) { shortcutController.change(to: $0) }
                }
                if let problem = shortcutController.problem {
                    Text(problem).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Press the shortcut again while Nomi is open to focus the question field. Escape closes it.")
            }
            Section {
                Toggle("Play sounds", isOn: $preferences.playsSounds)
                Toggle("Speak responses", isOn: $preferences.speaksResponses)
            } footer: {
                Text("Spoken responses use the built-in macOS voice and stay off unless you turn them on.")
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginProblem = nil
        } catch {
            Log.app.error("Launch at login change failed: \(error, privacy: .public)")
            launchAtLoginProblem = "macOS did not accept the change. Open System Settings > General > Login Items to adjust it there."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

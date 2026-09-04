import SwiftUI

struct PrivacySettingsView: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section("What stays on this Mac") {
                Text("The language model runs on this Mac. Your questions and its answers never leave it.")
                Text("Documentation you add, and everything learned from it, is stored in this app's Application Support folder.")
                Text("Conversations are kept locally and can be deleted at any time.")
                Text("There are no analytics and no advertising identifiers.")
            }
            Section("What uses the network") {
                Text("Weather questions contact Open-Meteo.")
                Text("Importing a web page fetches that page.")
                Text("MCP servers you add have their own behaviour and their own network access.")
            }
            Section {
                Toggle("Offline Mode", isOn: $preferences.offlineMode)
            } footer: {
                Text("Local chat, knowledge and automation keep working. Weather and web imports are unavailable and the assistant says so when a request needs them.")
            }
        }
        .formStyle(.grouped)
    }
}

import SwiftUI

struct PrivacySettingsView: View {
    var body: some View {
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
            Section("Offline Mode") {
                Text("Offline Mode is part of a later build. Local chat, knowledge and automation will keep working without a network.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

import SwiftUI

struct ToolsSettingsView: View {
    @Environment(Preferences.self) private var preferences
    let registry: ToolRegistry

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                Toggle("Ask before medium-risk actions", isOn: $preferences.confirmsMediumRisk)
            } footer: {
                Text("High-risk actions always ask. Low-risk actions such as reading the screen or checking the weather run on their own.")
            }
            Section {
                TextField("Home location", text: Binding(
                    get: { preferences.homeLocation ?? "" },
                    set: { preferences.homeLocation = $0.isEmpty ? nil : $0 }
                ), prompt: Text("City, for example Sydney"))
            } header: {
                Text("Weather")
            } footer: {
                Text("Used when you ask about the weather without naming a place.")
            }
            Section("Built-in tools") {
                ForEach(registry.allTools, id: \.name) { tool in
                    Toggle(isOn: Binding(
                        get: { !preferences.disabledToolNames.contains(tool.name) },
                        set: { enabled in
                            if enabled { preferences.disabledToolNames.remove(tool.name) } else { preferences.disabledToolNames.insert(tool.name) }
                            registry.setEnabled(enabled, name: tool.name)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(tool.name).font(.body.monospaced())
                                Text(riskLabel(tool.risk)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(tool.description).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func riskLabel(_ risk: RiskLevel) -> String {
        switch risk {
        case .low: "low risk"
        case .medium: "asks first"
        case .high: "always asks"
        }
    }
}

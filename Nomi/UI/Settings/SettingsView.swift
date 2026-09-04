import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, model, permissions, knowledge, skills, tools, mcp, privacy, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .model: "AI Model"
        case .permissions: "Permissions"
        case .knowledge: "Knowledge"
        case .skills: "Skills"
        case .tools: "Tools"
        case .mcp: "MCP"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .model: "cpu"
        case .permissions: "lock.shield"
        case .knowledge: "books.vertical"
        case .skills: "wand.and.stars"
        case .tools: "wrench.and.screwdriver"
        case .mcp: "point.3.connected.trianglepath.dotted"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var navigation: SettingsNavigation
    let registry: ToolRegistry

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $navigation.section) { section in
                Label(section.title, systemImage: section.symbol)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            detail
                .navigationTitle(navigation.section.title)
        }
        .frame(width: 720, height: 480)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.section {
        case .general: GeneralSettingsView()
        case .about: AboutSettingsView()
        case .model: ModelSettingsView()
        case .permissions: PendingSettingsView(text: "Permission states appear here once screen and Accessibility features exist.")
        case .knowledge: PendingSettingsView(text: "Documentation import arrives with the knowledge features.")
        case .skills: PendingSettingsView(text: "Saved skills appear here once actions can be recorded.")
        case .tools: ToolsSettingsView(registry: registry)
        case .mcp: PendingSettingsView(text: "MCP servers can be added here once the MCP client exists.")
        case .privacy: PrivacySettingsView()
        }
    }
}

/// Honest placeholder for a section whose feature has not been built yet.
struct PendingSettingsView: View {
    let text: String

    var body: some View {
        Form {
            Text(text)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

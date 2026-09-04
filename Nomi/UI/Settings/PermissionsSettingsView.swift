import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(PermissionsCenter.self) private var permissions

    var body: some View {
        Form {
            ForEach(PermissionKind.allCases) { kind in
                Section {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(kind.title)
                            Text(kind.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(permissions.state(of: kind).text)
                                .foregroundStyle(permissions.state(of: kind) == .granted ? Color.primary : Color.secondary)
                            HStack {
                                if permissions.state(of: kind) != .granted {
                                    Button("Allow…") { Task { await permissions.request(kind) } }
                                }
                                Button("System Settings") { permissions.openSystemSettings(for: kind) }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
    }
}

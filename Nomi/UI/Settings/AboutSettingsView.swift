import SwiftUI

struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            LabeledContent("Version", value: version)
            LabeledContent("Bundle identifier", value: Bundle.main.bundleIdentifier ?? "?")
            LabeledContent("Data folder", value: AppDirectories.applicationSupport.path(percentEncoded: false))
        }
        .formStyle(.grouped)
    }
}

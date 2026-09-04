import SwiftUI

enum OnboardingPage: Int, CaseIterable {
    case runsOnYourMac, downloadTheModel, giveItAccess, addKnowledge, ready

    var title: String {
        switch self {
        case .runsOnYourMac: "Runs on your Mac"
        case .downloadTheModel: "Download the model"
        case .giveItAccess: "Give it access"
        case .addKnowledge: "Add knowledge"
        case .ready: "Ready"
        }
    }

    var symbol: String {
        switch self {
        case .runsOnYourMac: "laptopcomputer"
        case .downloadTheModel: "arrow.down.circle"
        case .giveItAccess: "hand.raised"
        case .addKnowledge: "books.vertical"
        case .ready: "checkmark.circle"
        }
    }
}

/// Five pages styled like the notch surface: black, white text at the specified opacities, 8 pt grid.
struct OnboardingView: View {
    @Environment(ModelManager.self) private var modelManager
    let shortcut: KeyboardShortcut
    let onFinish: () -> Void
    @State private var page: OnboardingPage = .runsOnYourMac

    var body: some View {
        VStack(alignment: .leading, spacing: NotchStyle.groupSpacing) {
            Image(systemName: page.symbol)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(NotchStyle.secondaryText)
                .frame(height: 40)
            Text(page.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(NotchStyle.primaryText)
            pageBody
                .font(NotchStyle.body)
                .foregroundStyle(NotchStyle.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                pageIndicator
                Spacer()
                if page != .runsOnYourMac {
                    Button("Back", action: back)
                        .buttonStyle(NotchButtonStyle())
                }
                Button(page == .ready ? "Done" : "Continue", action: advance)
                    .buttonStyle(NotchButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 480, height: 400)
        .background(NotchStyle.surface)
        .animation(.easeInOut(duration: 0.15), value: page)
    }

    @ViewBuilder
    private var pageBody: some View {
        switch page {
        case .runsOnYourMac:
            VStack(alignment: .leading, spacing: NotchStyle.rowSpacing) {
                Text("Nomi lives in the notch. Its language model runs on this Mac, so questions, answers and documents stay here.")
                Text("No account, no API key and no cloud inference.")
            }
        case .downloadTheModel:
            OnboardingDownloadPage(model: modelManager.selectedModel)
        case .giveItAccess:
            VStack(alignment: .leading, spacing: NotchStyle.rowSpacing) {
                Text("To read and operate other apps, Nomi needs Accessibility permission. Nothing else is required to start.")
                Text("Permission handling arrives with the automation features.")
                    .foregroundStyle(NotchStyle.tertiaryText)
            }
        case .addKnowledge:
            VStack(alignment: .leading, spacing: NotchStyle.rowSpacing) {
                Text("Add manuals and documentation later in Settings so Nomi can answer questions about the apps you use.")
                Text("This step is optional.")
            }
        case .ready:
            VStack(alignment: .leading, spacing: NotchStyle.rowSpacing) {
                Text("Press \(shortcut.displayString) or click the notch to open Nomi.")
                Text("Change the shortcut any time in Settings.")
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: NotchStyle.rowSpacing) {
            ForEach(OnboardingPage.allCases, id: \.rawValue) { candidate in
                Circle()
                    .fill(candidate == page ? NotchStyle.primaryText : NotchStyle.tertiaryText)
                    .frame(width: 4, height: 4)
            }
        }
        .accessibilityLabel("Page \(page.rawValue + 1) of \(OnboardingPage.allCases.count)")
    }

    private func advance() {
        if let next = OnboardingPage(rawValue: page.rawValue + 1) {
            page = next
        } else {
            onFinish()
        }
    }

    private func back() {
        if let previous = OnboardingPage(rawValue: page.rawValue - 1) {
            page = previous
        }
    }
}

/// The download step: what will be fetched, how big it is, live progress, and readiness.
private struct OnboardingDownloadPage: View {
    @Environment(ModelManager.self) private var modelManager
    let model: ModelDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: NotchStyle.rowSpacing) {
            Text("Nomi answers with \(model.displayName), a one-time download of about \(model.approximateSizeText) stored in Application Support. You can pause and resume it, and remove it later in Settings.")
            HStack(spacing: NotchStyle.rowSpacing) {
                Text(stateText).foregroundStyle(NotchStyle.tertiaryText).monospacedDigit()
                Spacer()
                actionButton
            }
            .padding(.top, NotchStyle.rowSpacing)
            if let fraction = modelManager.installState(of: model).fractionCompleted {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(NotchStyle.primaryText)
            }
            if case .interrupted(_, let message?) = modelManager.installState(of: model) {
                Text(message).foregroundStyle(NotchStyle.tertiaryText)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch modelManager.installState(of: model) {
        case .notInstalled:
            Button("Download") { modelManager.download(model) }.buttonStyle(NotchButtonStyle())
        case .downloading:
            Button("Pause") { modelManager.cancelDownload(model) }.buttonStyle(NotchButtonStyle())
        case .interrupted:
            Button("Resume") { modelManager.download(model) }.buttonStyle(NotchButtonStyle())
        case .installed:
            EmptyView()
        }
    }

    private var stateText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        switch modelManager.installState(of: model) {
        case .notInstalled: return "Not downloaded"
        case .downloading(let completed, let total):
            return "\(formatter.string(fromByteCount: completed)) of \(formatter.string(fromByteCount: total))"
        case .interrupted(let completed, _): return "Paused at \(formatter.string(fromByteCount: completed))"
        case .installed: return "Ready"
        }
    }
}

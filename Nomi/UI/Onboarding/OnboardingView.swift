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
                        .buttonStyle(OnboardingButtonStyle(prominent: false))
                }
                Button(page == .ready ? "Done" : "Continue", action: advance)
                    .buttonStyle(OnboardingButtonStyle(prominent: true))
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
            VStack(alignment: .leading, spacing: NotchStyle.rowSpacing) {
                Text("The local model is a one-time download of several gigabytes and is stored in Application Support.")
                Text("Model download arrives in the next build. Nothing is downloaded yet.")
                    .foregroundStyle(NotchStyle.tertiaryText)
            }
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

private struct OnboardingButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NotchStyle.body)
            .foregroundStyle(prominent ? Color.black : NotchStyle.primaryText)
            .padding(.horizontal, 16)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: NotchStyle.controlRadius)
                    .fill(prominent ? NotchStyle.primaryText : NotchStyle.fieldFill)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

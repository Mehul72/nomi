import SwiftUI

/// The black surface that grows out of the camera housing, and the content it reveals.
struct NotchSurfaceView: View {
    @Bindable var model: NotchViewModel
    let assistant: Assistant
    let actions: NotchActions

    var body: some View {
        ZStack(alignment: .top) {
            NotchStyle.surface

            if model.state == .open {
                NotchOpenContent(model: model, assistant: assistant, actions: actions)
                    .frame(width: model.geometry.openWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(model.isContentVisible ? 1 : 0)
                    .allowsHitTesting(model.isContentVisible)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        actions.contentHeightChanged(height)
                    }
            }
        }
        // The surface animates; content that has not fitted yet is clipped rather than drawn on the desktop.
        .frame(width: model.surfaceSize.width, height: model.surfaceSize.height, alignment: .top)
        .clipShape(NotchSurfaceShape())
        .contentShape(NotchSurfaceShape())
        .onHover(perform: actions.hoverChanged)
        .onTapGesture {
            if model.state != .open { actions.open() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct NotchOpenContent: View {
    @Bindable var model: NotchViewModel
    let assistant: Assistant
    let actions: NotchActions
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: NotchStyle.rowSpacing) {
            inputField
            activity
        }
        .padding(.top, model.geometry.housing.height + NotchStyle.inset)
        .padding([.horizontal, .bottom], NotchStyle.inset)
        .onAppear { inputFocused = true }
        .onChange(of: model.isContentVisible) { _, visible in
            if visible { inputFocused = true }
        }
    }

    @ViewBuilder
    private var activity: some View {
        switch assistant.activity {
        case .idle:
            statusLine(model.statusText)
            if model.showsEscapeHint {
                Text("Press Escape to close")
                    .font(NotchStyle.caption)
                    .foregroundStyle(NotchStyle.secondaryText)
            }
        case .thinking(let verb):
            thinkingLine(verb)
        case .acting(let status, let steps):
            ActivityTimeline(steps: steps)
            if !status.isEmpty { thinkingLine(status) }
        case .answering(let text, let steps):
            ActivityTimeline(steps: steps)
            AnswerView(text: text, maxHeight: answerMaxHeight, openConversation: actions.openConversation)
        case .answered(let text, let steps):
            ActivityTimeline(steps: steps)
            AnswerView(text: text, maxHeight: answerMaxHeight, openConversation: actions.openConversation)
        case .confirming(let request, let steps):
            ActivityTimeline(steps: steps)
            ConfirmationView(request: request) { allow in assistant.resolveConfirmation(allow: allow) }
        case .failed(let message, let steps):
            ActivityTimeline(steps: steps)
            Text(message)
                .font(NotchStyle.body)
                .foregroundStyle(NotchStyle.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Room left for the answer once the housing, insets, field and a timeline row are accounted for.
    private var answerMaxHeight: CGFloat {
        let overhead = model.geometry.housing.height + NotchStyle.inset * 2 + NotchStyle.fieldHeight + NotchStyle.rowSpacing * 2
        let timeline = CGFloat(min(assistant.activity.steps.count, ActivityTimeline.maxVisible)) * 18
        return max(model.geometry.maxOpenHeight - overhead - timeline, 60)
    }

    private func statusLine(_ text: String) -> some View {
        Text(text)
            .font(NotchStyle.caption2)
            .foregroundStyle(NotchStyle.tertiaryText)
            .lineLimit(1)
    }

    private func thinkingLine(_ verb: String) -> some View {
        HStack(spacing: NotchStyle.rowSpacing) {
            BreathingDot()
            Text(verb)
                .font(NotchStyle.caption)
                .foregroundStyle(NotchStyle.secondaryText)
                .lineLimit(1)
        }
        .frame(height: 16)
    }

    private var inputField: some View {
        HStack(spacing: NotchStyle.rowSpacing) {
            TextField("Ask anything", text: $model.input)
                .textFieldStyle(.plain)
                .font(NotchStyle.body)
                .foregroundStyle(NotchStyle.primaryText)
                .focused($inputFocused)
                .onSubmit(actions.submit)
                .onExitCommand(perform: actions.escape)

            Button(action: actions.microphoneTapped) {
                Image(systemName: "mic")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(NotchStyle.secondaryText)
                    .frame(width: 24, height: 24)
                    .contentShape(RoundedRectangle(cornerRadius: NotchStyle.controlRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask by voice")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: NotchStyle.fieldHeight)
        .background(Capsule().fill(NotchStyle.fieldFill))
        .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: inputFocused ? 1 : 0))
    }
}

/// Completed steps, newest at the bottom, at most six visible.
struct ActivityTimeline: View {
    static let maxVisible = 6
    let steps: [ActivityStep]

    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(steps.suffix(Self.maxVisible)) { step in
                    HStack(spacing: NotchStyle.rowSpacing) {
                        Image(systemName: step.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(NotchStyle.secondaryText)
                            .frame(width: 14)
                        Text(step.text)
                            .font(NotchStyle.caption)
                            .foregroundStyle(step.isError ? NotchStyle.primaryText : NotchStyle.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(height: 14)
                }
            }
        }
    }
}

/// The answer, selectable, scrolling inside the panel up to the height cap.
private struct AnswerView: View {
    let text: String
    let maxHeight: CGFloat
    let openConversation: () -> Void
    @State private var naturalHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            Text(MarkdownText.rendered(text))
                .font(NotchStyle.body)
                .foregroundStyle(NotchStyle.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { naturalHeight = $0 }
        }
        .frame(height: min(max(naturalHeight, 16), maxHeight))
        .scrollIndicators(.automatic)
        if naturalHeight > maxHeight {
            Button("Open conversation", action: openConversation)
                .buttonStyle(NotchButtonStyle())
        }
    }

}

/// A plain sentence and two buttons. Allow is the default only for medium risk.
private struct ConfirmationView: View {
    let request: ConfirmationRequest
    let respond: (Bool) -> Void

    var body: some View {
        Text(request.text)
            .font(NotchStyle.body)
            .foregroundStyle(NotchStyle.primaryText)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: NotchStyle.rowSpacing) {
            Spacer()
            Button("Cancel") { respond(false) }
                .buttonStyle(NotchButtonStyle())
                .keyboardShortcut(.cancelAction)
            if request.allowIsDefault {
                Button("Allow") { respond(true) }
                    .buttonStyle(NotchButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Allow") { respond(true) }
                    .buttonStyle(NotchButtonStyle(prominent: true))
            }
        }
    }
}

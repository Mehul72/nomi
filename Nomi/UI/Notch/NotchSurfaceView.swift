import SwiftUI

/// The black surface that grows out of the camera housing, and the content it reveals.
struct NotchSurfaceView: View {
    @Bindable var model: NotchViewModel
    let actions: NotchActions

    var body: some View {
        ZStack(alignment: .top) {
            NotchSurfaceShape()
                .fill(NotchStyle.surface)
                .frame(width: model.surfaceSize.width, height: model.surfaceSize.height)
                .contentShape(NotchSurfaceShape())
                .onHover(perform: actions.hoverChanged)
                .onTapGesture {
                    if model.state != .open { actions.open() }
                }

            if model.state == .open {
                NotchOpenContent(model: model, actions: actions)
                    .frame(width: model.geometry.openWidth)
                    .opacity(model.isContentVisible ? 1 : 0)
                    .allowsHitTesting(model.isContentVisible)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        actions.contentHeightChanged(height)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct NotchOpenContent: View {
    @Bindable var model: NotchViewModel
    let actions: NotchActions
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: NotchStyle.rowSpacing) {
            inputField
            Text(model.statusText)
                .font(NotchStyle.caption2)
                .foregroundStyle(NotchStyle.tertiaryText)
                .lineLimit(1)
            if model.showsEscapeHint {
                Text("Press Escape to close")
                    .font(NotchStyle.caption)
                    .foregroundStyle(NotchStyle.secondaryText)
            }
        }
        .padding(.top, model.geometry.housing.height + NotchStyle.inset)
        .padding([.horizontal, .bottom], NotchStyle.inset)
        .onAppear { inputFocused = true }
        .onChange(of: model.isContentVisible) { _, visible in
            if visible { inputFocused = true }
        }
    }

    private var inputField: some View {
        HStack(spacing: NotchStyle.rowSpacing) {
            TextField("Ask anything", text: $model.input)
                .textFieldStyle(.plain)
                .font(NotchStyle.body)
                .foregroundStyle(NotchStyle.primaryText)
                .focused($inputFocused)
                .onSubmit(actions.submit)
                .onExitCommand(perform: actions.close)

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

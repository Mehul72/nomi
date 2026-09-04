import AppKit
import SwiftUI

/// Drives one notch surface on one display: window frames, state transitions and their choreography.
final class NotchPanelController: NSObject {
    let displayID: CGDirectDisplayID
    let panel = NotchPanel()
    let model: NotchViewModel
    let assistant: Assistant
    var onClosed: (() -> Void)?
    var onOpenConversation: (() -> Void)?

    private let hostingView: NSHostingView<NotchSurfaceView>
    private var hoverTask: Task<Void, Never>?
    /// Incremented on every open or close so a stale delayed fade cannot land on a newer state.
    private var openGeneration = 0

    init(displayID: CGDirectDisplayID, display: DisplayLayout, showsEscapeHint: Bool, modelManager: ModelManager, assistant: Assistant) {
        self.displayID = displayID
        self.assistant = assistant
        model = NotchViewModel(geometry: NotchGeometry(display: display), showsEscapeHint: showsEscapeHint, modelManager: modelManager)
        hostingView = NSHostingView(rootView: NotchSurfaceView(model: model, assistant: assistant, actions: .none))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        super.init()

        hostingView.rootView = NotchSurfaceView(model: model, assistant: assistant, actions: NotchActions(
            open: { [weak self] in self?.open() },
            close: { [weak self] in self?.close() },
            hoverChanged: { [weak self] inside in self?.hoverChanged(inside) },
            submit: { [weak self] in self?.submit() },
            escape: { [weak self] in self?.escapePressed() },
            microphoneTapped: { [weak self] in self?.microphoneTapped() },
            openConversation: { [weak self] in self?.openConversation() },
            contentHeightChanged: { [weak self] height in self?.contentHeightChanged(height) }
        ))
        panel.onCancel = { [weak self] in self?.escapePressed() }

        // The window always spans the largest surface; transparent pixels pass clicks through to whatever is beneath.
        panel.setFrame(model.geometry.maximumFrame, display: false)
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self, selector: #selector(panelResignedKey), name: NSWindow.didResignKeyNotification, object: panel
        )
    }

    @objc private func panelResignedKey() {
        guard model.state == .open else { return }
        close()
    }

    var isOpen: Bool { model.state == .open }

    func update(display: DisplayLayout) {
        model.geometry = NotchGeometry(display: display)
        panel.setFrame(model.geometry.maximumFrame, display: true)
    }

    func open() {
        hoverTask?.cancel()
        if model.state == .open {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        openGeneration += 1
        let generation = openGeneration
        model.input = ""
        model.transientStatus = nil

        panel.makeKeyAndOrderFront(nil)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

        if reduceMotion {
            animate(.linear(duration: NotchStyle.reducedMotionDuration)) {
                model.state = .open
                model.isContentVisible = true
            }
            return
        }

        animate(.spring(NotchStyle.openSpring)) { model.state = .open }
        let fadeDelay = NotchStyle.travelTime(of: NotchStyle.openSpring, fraction: 0.6)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(fadeDelay))
            guard let self, self.openGeneration == generation, self.model.state == .open else { return }
            withAnimation(.linear(duration: NotchStyle.contentFadeDuration)) {
                self.model.isContentVisible = true
            }
        }
    }

    func close() {
        hoverTask?.cancel()
        guard model.state != .idle else { return }
        guard model.state == .open else {
            animate(.spring(NotchStyle.hoverSpring)) { model.state = .idle }
            return
        }
        openGeneration += 1
        if model.showsEscapeHint {
            model.showsEscapeHint = false
        }

        if reduceMotion {
            animate(.linear(duration: NotchStyle.reducedMotionDuration)) {
                model.isContentVisible = false
                model.state = .idle
            } completion: { [weak self] in self?.finishClose() }
            return
        }

        animate(.linear(duration: NotchStyle.contentFadeDuration)) {
            model.isContentVisible = false
        } completion: { [weak self] in
            guard let self, self.model.state == .open else { return }
            self.animate(.spring(NotchStyle.openSpring)) {
                self.model.state = .idle
            } completion: { [weak self] in self?.finishClose() }
        }
    }

    private func finishClose() {
        // Ordering out and back in hands keyboard focus to whatever app was in front, without activating this one.
        if panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        assistant.dismissResult()
        onClosed?()
    }

    private func hoverChanged(_ inside: Bool) {
        guard model.state != .open else { return }
        hoverTask?.cancel()
        if inside {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(NotchStyle.hoverDelay))
                guard let self, !Task.isCancelled, self.model.state == .idle else { return }
                self.animate(self.reduceMotion ? .linear(duration: NotchStyle.reducedMotionDuration) : .spring(NotchStyle.hoverSpring)) {
                    self.model.state = .hovering
                }
            }
        } else if model.state == .hovering {
            animate(reduceMotion ? .linear(duration: NotchStyle.reducedMotionDuration) : .spring(NotchStyle.hoverSpring)) {
                model.state = .idle
            }
        }
    }

    private func contentHeightChanged(_ height: CGFloat) {
        guard height != model.contentHeight else { return }
        guard model.state == .open else {
            model.contentHeight = height
            return
        }
        animate(reduceMotion ? .linear(duration: NotchStyle.reducedMotionDuration) : .spring(NotchStyle.openSpring)) {
            model.contentHeight = height
        }
    }

    /// Escape stops whatever is running; a second press, or a press while idle, closes the surface.
    func escapePressed() {
        if assistant.isBusy {
            assistant.cancel()
            return
        }
        close()
    }

    private func submit() {
        if case .confirming(let request, _) = assistant.activity, model.input.isEmpty {
            if request.allowIsDefault { assistant.resolveConfirmation(allow: true) }
            return
        }
        let question = model.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        model.input = ""
        model.transientStatus = nil
        assistant.ask(question)
    }

    private func openConversation() {
        onOpenConversation?()
        close()
    }

    private func microphoneTapped() {
        model.transientStatus = "Voice input is not available yet"
    }

    private func animate(_ animation: Animation, _ change: () -> Void, completion: (() -> Void)? = nil) {
        withAnimation(animation, completionCriteria: .removed, change) {
            completion?()
        }
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

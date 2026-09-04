import AppKit

/// Keeps one notch surface per display and routes open, close and toggle requests to the right one.
final class NotchCoordinator: NSObject {
    private(set) var controllers: [NotchPanelController] = []
    private let preferences: Preferences
    private let modelManager: ModelManager
    private let assistant: Assistant
    var onOpenConversation: (() -> Void)?

    init(preferences: Preferences, modelManager: ModelManager, assistant: Assistant) {
        self.preferences = preferences
        self.modelManager = modelManager
        self.assistant = assistant
        super.init()
        rebuildForCurrentScreens()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    @objc private func screensChanged() {
        rebuildForCurrentScreens()
    }

    var openController: NotchPanelController? {
        controllers.first { $0.isOpen }
    }

    func toggle() {
        if let openController {
            openController.close()
        } else {
            open()
        }
    }

    func open() {
        if let openController {
            openController.open()
            return
        }
        controller(for: screenUnderMouse())?.open()
    }

    func closeAll() {
        controllers.forEach { $0.close() }
    }

    /// Opens the surface on the screen under the mouse and asks the question straight away.
    func ask(_ question: String) {
        open()
        assistant.ask(question)
    }

    #if DEBUG
    func logHitTestProbe() {
        for controller in controllers {
            let frame = controller.panel.frame
            let housing = controller.model.geometry.housing
            let beside = CGPoint(x: frame.minX + 8, y: frame.maxY - 8)
            let inside = CGPoint(x: housing.midX, y: housing.midY)
            let below = CGPoint(x: housing.midX, y: frame.minY + 8)
            let own = controller.panel.windowNumber
            for (name, point) in [("beside", beside), ("housing", inside), ("below", below)] {
                let hit = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
                Log.notch.notice("probe \(name, privacy: .public) state=\(String(describing: controller.model.state), privacy: .public) hit=\(hit) own=\(own) frame=\(String(describing: frame), privacy: .public)")
            }
        }
    }
    #endif

    private func controller(for screen: NSScreen?) -> NotchPanelController? {
        guard let screen, let id = screen.displayID else { return controllers.first }
        return controllers.first { $0.displayID == id } ?? controllers.first
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    /// Matches surfaces to displays by ID so a display that is still attached keeps its state.
    private func rebuildForCurrentScreens() {
        var remaining = controllers
        var updated: [NotchPanelController] = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let layout = DisplayLayout(screen: screen)
            if let index = remaining.firstIndex(where: { $0.displayID == id }) {
                let existing = remaining.remove(at: index)
                existing.update(display: layout)
                updated.append(existing)
            } else {
                let controller = NotchPanelController(
                    displayID: id, display: layout, showsEscapeHint: !preferences.hasClosedNotchOnce,
                    modelManager: modelManager, assistant: assistant
                )
                controller.onClosed = { [weak self] in self?.preferences.hasClosedNotchOnce = true }
                controller.onOpenConversation = { [weak self] in self?.onOpenConversation?() }
                updated.append(controller)
            }
        }
        remaining.forEach { $0.panel.orderOut(nil) }
        controllers = updated
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

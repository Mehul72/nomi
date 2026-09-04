import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences()
    private(set) lazy var modelManager = ModelManager(preferences: preferences)
    private(set) lazy var toolRegistry: ToolRegistry = {
        let registry = ToolRegistry(tools: [
            CurrentTimeTool(), FrontmostAppTool(), RunningAppsTool(), OpenAppTool(), OpenURLTool(), ShowNotificationTool(),
            SearchFilesTool(), ReadTextFileTool(), CreateTextFileTool(), MoveFileTool(),
            ReadClipboardTool(), WriteClipboardTool(),
            WeatherTool(),
        ])
        for name in preferences.disabledToolNames {
            registry.setEnabled(false, name: name)
        }
        return registry
    }()
    private(set) lazy var assistant = Assistant(modelManager: modelManager, preferences: preferences, registry: toolRegistry)
    private lazy var conversation = ConversationWindowController(assistant: assistant)
    private(set) lazy var shortcut = ShortcutController(preferences: preferences) { [weak self] in self?.notch?.open() }
    private(set) lazy var onboarding = OnboardingWindowController(preferences: preferences, modelManager: modelManager)
    private lazy var settings = SettingsWindowController(preferences: preferences, shortcut: shortcut, modelManager: modelManager, registry: toolRegistry)
    private var statusItem: StatusItemController?
    private var notch: NotchCoordinator?
    private var urlCommands: URLCommandHandler?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !ProcessInfo.processInfo.isRunningUnitTests else { return }
        urlCommands = URLCommandHandler { [weak self] command in self?.handle(command) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit test runner hosts this app; it must not put panels on screen.
        guard !ProcessInfo.processInfo.isRunningUnitTests else { return }

        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.build()
        FrontmostAppTracker.start()
        statusItem = StatusItemController(
            preferences: preferences,
            showWelcome: { [weak self] in self?.onboarding.show() },
            showSettings: { [weak self] in self?.showSettings(nil) }
        )
        notch = NotchCoordinator(preferences: preferences, modelManager: modelManager, assistant: assistant)
        notch?.onOpenConversation = { [weak self] in self?.conversation.show() }
        _ = shortcut
        if !preferences.hasCompletedOnboarding {
            onboarding.show()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func showSettings(_ sender: Any?) {
        settings.show()
    }

    private func handle(_ command: URLCommand) {
        switch command {
        case .open: notch?.open()
        case .close: notch?.closeAll()
        case .toggle: notch?.toggle()
        case .welcome: onboarding.show()
        case .settings(let section): settings.show(section: section)
        case .ask(let question): notch?.ask(question)
        #if DEBUG
        case .probe: notch?.logHitTestProbe()
        case .closewindows:
            settings.close()
            onboarding.close()
            conversation.close()
        case .download(let id):
            modelManager.download(id.flatMap(ModelCatalog.descriptor) ?? modelManager.selectedModel)
        case .load:
            Task { _ = await modelManager.loadedLanguageModel() }
        case .verify(let id):
            modelManager.verify(id.flatMap(ModelCatalog.descriptor) ?? modelManager.selectedModel)
        #endif
        }
    }
}

extension ProcessInfo {
    var isRunningUnitTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }
}

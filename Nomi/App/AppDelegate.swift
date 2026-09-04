import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences()
    private(set) lazy var shortcut = ShortcutController(preferences: preferences) { [weak self] in self?.notch?.open() }
    private(set) lazy var onboarding = OnboardingWindowController(preferences: preferences)
    private lazy var settings = SettingsWindowController(preferences: preferences, shortcut: shortcut)
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
        statusItem = StatusItemController(
            preferences: preferences,
            showWelcome: { [weak self] in self?.onboarding.show() },
            showSettings: { [weak self] in self?.showSettings(nil) }
        )
        notch = NotchCoordinator(preferences: preferences)
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
        case .settings: showSettings(nil)
        #if DEBUG
        case .probe: notch?.logHitTestProbe()
        case .closewindows:
            settings.close()
            onboarding.close()
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

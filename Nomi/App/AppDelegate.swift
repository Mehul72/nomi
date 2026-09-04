import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
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
        statusItem = StatusItemController()
        notch = NotchCoordinator(preferences: preferences)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func handle(_ command: URLCommand) {
        switch command {
        case .open: notch?.open()
        case .close: notch?.closeAll()
        case .toggle: notch?.toggle()
        #if DEBUG
        case .probe: notch?.logHitTestProbe()
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

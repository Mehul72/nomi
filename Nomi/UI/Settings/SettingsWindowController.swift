import AppKit
import SwiftUI

/// The Settings window, created on first use and reused afterwards.
final class SettingsWindowController {
    private var window: NSWindow?
    private let preferences: Preferences
    private let shortcut: ShortcutController
    private let modelManager: ModelManager
    private let registry: ToolRegistry
    private let navigation = SettingsNavigation()

    init(preferences: Preferences, shortcut: ShortcutController, modelManager: ModelManager, registry: ToolRegistry) {
        self.preferences = preferences
        self.shortcut = shortcut
        self.modelManager = modelManager
        self.registry = registry
    }

    func show(section: SettingsSection? = nil) {
        if let section { navigation.section = section }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let content = SettingsView(navigation: navigation, registry: registry)
            .environment(preferences)
            .environment(shortcut)
            .environment(modelManager)
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 720, height: 480))
        window.center()
        return window
    }
}

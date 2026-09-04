import AppKit
import SwiftUI

/// The Settings window, created on first use and reused afterwards.
final class SettingsWindowController {
    private var window: NSWindow?
    private let preferences: Preferences
    private let shortcut: ShortcutController

    init(preferences: Preferences, shortcut: ShortcutController) {
        self.preferences = preferences
        self.shortcut = shortcut
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let content = SettingsView()
            .environment(preferences)
            .environment(shortcut)
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

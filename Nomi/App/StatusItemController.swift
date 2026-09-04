import AppKit
import Observation

/// The menu bar item is the conventional way to reach Settings and Quit in an app with no Dock icon.
final class StatusItemController {
    private var statusItem: NSStatusItem?
    private let preferences: Preferences
    private let showWelcome: () -> Void
    private let showSettings: () -> Void

    init(preferences: Preferences, showWelcome: @escaping () -> Void, showSettings: @escaping () -> Void) {
        self.preferences = preferences
        self.showWelcome = showWelcome
        self.showSettings = showSettings
        observeVisibility()
    }

    private func observeVisibility() {
        withObservationTracking {
            setVisible(preferences.showsMenuBarIcon)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeVisibility() }
        }
    }

    private func setVisible(_ visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Nomi")
            item.menu = buildMenu()
            statusItem = item
        } else if !visible, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let welcome = NSMenuItem(title: "Welcome…", action: #selector(openWelcome), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Nomi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func openWelcome() {
        showWelcome()
    }
}

import AppKit
import SwiftUI

/// Shows the welcome flow in its own window and remembers completion.
final class OnboardingWindowController {
    private var window: NSWindow?
    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let content = OnboardingView(shortcut: preferences.shortcut) { [weak self] in self?.finish() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to Nomi"
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        // The hosting view has no size until layout, so give the window its size before centring it.
        window.setContentSize(NSSize(width: 480, height: 400))
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }

    private func finish() {
        preferences.hasCompletedOnboarding = true
        close()
    }
}

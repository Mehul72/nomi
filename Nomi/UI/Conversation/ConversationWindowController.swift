import AppKit
import SwiftUI

final class ConversationWindowController {
    private var window: NSWindow?
    private let assistant: Assistant

    init(assistant: Assistant) {
        self.assistant = assistant
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
        let window = NSWindow(contentViewController: NSHostingController(rootView: ConversationView(assistant: assistant)))
        window.title = "Conversation"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 600))
        window.center()
        return window
    }
}

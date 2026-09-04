import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that shows the current shortcut and records a new one from the next key press.
struct ShortcutRecorderView: View {
    let shortcut: KeyboardShortcut
    let onChange: (KeyboardShortcut) -> Void
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? "Press keys…" : shortcut.displayString)
                .frame(minWidth: 96)
        }
        .onDisappear(perform: stopRecording)
        .accessibilityLabel(isRecording ? "Recording shortcut" : "Shortcut \(shortcut.displayString)")
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            MainActor.assumeIsolated {
                record(keyCode: keyCode, modifiers: modifiers)
            }
            // Every key press while recording belongs to the recorder, so nothing else reacts to it.
            return nil
        }
    }

    private func record(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        if keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        let candidate = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
        guard candidate.isUsableGlobally else { return }
        onChange(candidate)
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}

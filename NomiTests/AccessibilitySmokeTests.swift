import AppKit
import ApplicationServices
import Testing
@testable import Nomi

/// Manual smoke test against TextEdit. Runs only when the test host has Accessibility permission;
/// otherwise it records nothing rather than claiming a pass it did not earn.
@MainActor
struct AccessibilitySmokeTests {
    @Test(.enabled(if: AXIsProcessTrusted(), "Grant Accessibility to the Nomi test host to run this"))
    func inspectsAndTypesIntoTextEdit() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let url = try #require(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit"))
        let textEdit = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        try await Task.sleep(for: .seconds(2))
        InputSynthesizer.press(try InputSynthesizer.parse("cmd+n"), to: textEdit.processIdentifier)
        try await Task.sleep(for: .seconds(1))

        let inspector = AccessibilityInspector()
        let snapshot = try inspector.inspect(app: textEdit)
        #expect(snapshot.bundleID == "com.apple.TextEdit")
        let textArea = try #require(snapshot.elements.first { $0.role == "AXTextArea" })
        try inspector.setValue("Nomi smoke test", on: textArea.id)
        let after = try inspector.inspect(app: textEdit)
        #expect(after.elements.first { $0.role == "AXTextArea" }?.value == "Nomi smoke test")
        InputSynthesizer.press(try InputSynthesizer.parse("cmd+z"), to: textEdit.processIdentifier)
    }
}

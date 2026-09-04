import AppKit
import CoreGraphics
import Foundation

/// What the assistant learned about the front window, cheapest source first.
nonisolated struct ScreenDescription: Sendable {
    enum Source: String, Sendable {
        case accessibility, ocr, both
    }

    var appName: String
    var windowTitle: String?
    var source: Source
    var accessibilityText: String
    var recognizedLines: [RecognizedLine]
    var capture: ScreenCapture.WindowImage?

    /// Text for the model: Accessibility text first, recognised text when it adds something.
    var text: String {
        var sections = ["App: \(appName)" + (windowTitle.map { ", window: \($0)" } ?? "")]
        if !accessibilityText.isEmpty {
            sections.append("Text exposed by the app:\n\(accessibilityText)")
        }
        if !recognizedLines.isEmpty {
            sections.append("Text recognised from the window image:\n\(TextRecognizer.paragraphs(from: recognizedLines))")
        }
        return sections.joined(separator: "\n\n")
    }

    /// Recognised lines with their screen regions, so an action can target them.
    var regionListing: String {
        recognizedLines.map { line in
            let f = line.frame
            return "[\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))] \(line.text)"
        }.joined(separator: "\n")
    }
}

nonisolated enum ScreenReadingError: LocalizedError {
    case nothingReadable(appName: String, accessibility: Bool, screenRecording: Bool)

    var errorDescription: String? {
        switch self {
        case .nothingReadable(let appName, let accessibility, let screenRecording):
            var missing: [String] = []
            if !accessibility { missing.append("Accessibility") }
            if !screenRecording { missing.append("Screen Recording") }
            if missing.isEmpty {
                return "\(appName) exposes no readable text and its window could not be captured."
            }
            return "I can see \(appName), but macOS has not granted \(missing.joined(separator: " or ")) permission yet, so I cannot read its window. Turn it on in System Settings > Privacy & Security."
        }
    }
}

/// Reads the front window: Accessibility first, then Vision OCR on a capture when that exposes little.
final class ScreenReader: Sendable {
    /// Below this many characters from Accessibility, the window is probably drawn rather than described.
    static let thinTextThreshold = 200

    let automation: AutomationContext

    init(automation: AutomationContext) {
        self.automation = automation
    }

    func read(app: NSRunningApplication, forceCapture: Bool = false) async throws -> ScreenDescription {
        let appName = app.localizedName ?? "the app"
        var accessibilityText = ""
        var windowTitle: String?
        let accessibilityGranted = AXIsProcessTrusted()
        if accessibilityGranted {
            if let snapshot = try? automation.inspector.inspect(app: app, maxDepth: 2, maxElements: 4) {
                windowTitle = snapshot.windowTitle
            }
            accessibilityText = (try? automation.inspector.readableText(app: app)) ?? ""
        }

        var lines: [RecognizedLine] = []
        var capture: ScreenCapture.WindowImage?
        let needsCapture = forceCapture || accessibilityText.count < Self.thinTextThreshold
        if needsCapture, CGPreflightScreenCaptureAccess() {
            let image = try await ScreenCapture.captureFrontWindow(of: app)
            capture = image
            windowTitle = windowTitle ?? image.title
            lines = try await TextRecognizer.recognize(image)
        }

        guard !accessibilityText.isEmpty || !lines.isEmpty || capture != nil else {
            throw ScreenReadingError.nothingReadable(appName: appName, accessibility: accessibilityGranted, screenRecording: CGPreflightScreenCaptureAccess())
        }
        let source: ScreenDescription.Source = switch (accessibilityText.isEmpty, lines.isEmpty) {
        case (false, false): .both
        case (false, true): .accessibility
        default: .ocr
        }
        return ScreenDescription(appName: appName, windowTitle: windowTitle, source: source, accessibilityText: accessibilityText, recognizedLines: lines, capture: capture)
    }
}

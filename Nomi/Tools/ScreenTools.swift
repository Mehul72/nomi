import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Describes an image with the optional local vision model. The image is only produced when the model is turned on.
typealias VisionDescriber = @Sendable (_ image: @Sendable () async throws -> CGImage, _ question: String) async throws -> String?

struct DescribeScreenTool: Tool {
    let name = "describe_screen"
    let description = "Reads what is on the user's screen: the front window's text through Accessibility, recognised text from a capture when the app exposes little, and, when the vision model is enabled, a visual description of images, charts and layout. Use it for questions like what's on my screen, what does this error mean, summarise this page."
    let parameters = [
        ToolParameterSpec.optional("question", .string, "What the user wants to know about the screen, passed to the vision model when it is enabled"),
    ]
    let risk = RiskLevel.low
    let symbol = "eye"
    let reader: ScreenReader
    let vision: VisionDescriber

    func activityLabel(for arguments: ToolArguments) -> String { "Looking at your screen" }
    func confirmationText(for arguments: ToolArguments) -> String { "Read the front window?" }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let app = try reader.automation.targetApp()
        let question = try arguments.optionalString("question") ?? "Describe what is shown."
        let description = try await reader.read(app: app)
        var text = description.text
        var summary = "Read \(description.appName)"
        let existingCapture = description.capture
        let image: @Sendable () async throws -> CGImage = {
            if let existingCapture { return existingCapture.image }
            return try await ScreenCapture.captureFrontWindow(of: app).image
        }
        if let visual = try await vision(image, question) {
            text += "\n\nVisual description from the vision model:\n\(visual)"
            summary = "Looked at \(description.appName)"
        }
        return ToolResult(content: text, summary: summary)
    }
}

struct ReadScreenTextTool: Tool {
    let name = "read_screen_text"
    let description = "Recognises the text in the front window from a capture and returns each line with its screen position [x,y width x height], so a later action can target it. Use inspect_ui first when the app exposes controls."
    let parameters: [ToolParameterSpec] = []
    let risk = RiskLevel.low
    let symbol = "text.viewfinder"
    let reader: ScreenReader

    func activityLabel(for arguments: ToolArguments) -> String { "Reading text on your screen" }
    func confirmationText(for arguments: ToolArguments) -> String { "Capture the front window to read its text?" }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let app = try reader.automation.targetApp()
        let description = try await reader.read(app: app, forceCapture: true)
        guard !description.recognizedLines.isEmpty else {
            return ToolResult(content: description.text, summary: "No text recognised in \(description.appName)")
        }
        return ToolResult(content: "App: \(description.appName)\n" + description.regionListing, summary: "Recognised \(description.recognizedLines.count) lines in \(description.appName)")
    }
}

struct CaptureWindowTool: Tool {
    let name = "capture_window"
    let description = "Captures the front window to a PNG file in Nomi's Application Support folder and returns its path and size. Only when the user asks for a capture."
    let parameters: [ToolParameterSpec] = []
    let risk = RiskLevel.low
    let symbol = "camera.viewfinder"
    let reader: ScreenReader

    func activityLabel(for arguments: ToolArguments) -> String { "Capturing the window" }
    func confirmationText(for arguments: ToolArguments) -> String { "Capture the front window to a file?" }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let app = try reader.automation.targetApp()
        let capture = try await ScreenCapture.captureFrontWindow(of: app)
        let folder = AppDirectories.captures
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let url = folder.appending(path: "\(capture.appName)-\(stamp).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ToolError.failed("The capture could not be saved.")
        }
        CGImageDestinationAddImage(destination, capture.image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ToolError.failed("The capture could not be written.") }
        return ToolResult(
            content: "Saved \(url.path(percentEncoded: false)) (\(capture.image.width)x\(capture.image.height) pixels).",
            summary: "Captured \(capture.appName)"
        )
    }
}

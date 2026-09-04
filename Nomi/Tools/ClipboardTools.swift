import AppKit
import Foundation

struct ReadClipboardTool: Tool {
    let name = "read_clipboard"
    let description = "Returns the text currently on the clipboard, if any."
    let parameters: [ToolParameterSpec] = []
    let risk = RiskLevel.low
    let symbol = "doc.on.clipboard"

    func activityLabel(for arguments: ToolArguments) -> String { "Reading the clipboard" }
    func confirmationText(for arguments: ToolArguments) -> String { "Read the clipboard?" }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let text = await MainActor.run { NSPasteboard.general.string(forType: .string) }
        guard let text, !text.isEmpty else {
            return ToolResult(content: "The clipboard holds no text.", summary: "Clipboard is empty")
        }
        let limit = 20_000
        let clipped = text.count > limit ? String(text.prefix(limit)) + "\n[truncated]" : text
        return ToolResult(content: clipped, summary: "Read \(text.count) characters from the clipboard")
    }
}

struct WriteClipboardTool: Tool {
    let name = "write_clipboard"
    let description = "Replaces the clipboard contents with the given text."
    let parameters = [ToolParameterSpec.required("text", .string, "The text to put on the clipboard")]
    let risk = RiskLevel.medium
    let symbol = "doc.on.clipboard"

    func activityLabel(for arguments: ToolArguments) -> String { "Copying to the clipboard" }

    func confirmationText(for arguments: ToolArguments) -> String {
        let text = (try? arguments.string("text")) ?? ""
        let preview = text.count > 60 ? String(text.prefix(60)) + "…" : text
        return "Replace the clipboard with \"\(preview)\"?"
    }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let text = try arguments.string("text")
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        return ToolResult(content: "Copied \(text.count) characters to the clipboard.", summary: "Copied \(text.count) characters")
    }
}

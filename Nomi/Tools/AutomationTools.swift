import AppKit
import Foundation

/// Shared state for the UI tools: the inspector that owns element IDs, and how to find the target app.
final class AutomationContext: Sendable {
    let inspector = AccessibilityInspector()

    /// The app the user is working in, never Nomi itself.
    func targetApp() throws -> NSRunningApplication {
        guard let app = MainActor.assumeIsolated({ FrontmostAppTracker.shared.current }) else {
            throw AutomationError.noFrontmostApp
        }
        return app
    }
}

struct InspectUITool: Tool {
    let name = "inspect_ui"
    let description = "Reads the controls of the front window of the app the user is using through Accessibility. Returns elements with temporary IDs (e1, e2, …), their role, title, value and available actions. Call it again after any action that changes the screen; IDs expire."
    let parameters = [
        ToolParameterSpec.optional("element_id", .string, "Inspect only this element and its descendants, from a previous inspection"),
        ToolParameterSpec.optional("depth", .integer, "How many levels deep to read (default 12, max 25)"),
    ]
    let risk = RiskLevel.low
    let symbol = "rectangle.3.group"
    let context: AutomationContext

    func activityLabel(for arguments: ToolArguments) -> String { "Inspecting the window" }
    func confirmationText(for arguments: ToolArguments) -> String { "Read the window's controls?" }

    func execute(_ arguments: ToolArguments, context toolContext: ToolContext) async throws -> ToolResult {
        let app = try context.targetApp()
        let root = try arguments.optionalString("element_id")
        let depth = min(max(try arguments.optionalInteger("depth") ?? AccessibilityInspector.maxDepth, 1), 25)
        let snapshot = try context.inspector.inspect(app: app, root: root, maxDepth: depth)
        return ToolResult(content: snapshot.text, summary: "Inspected \(snapshot.appName): \(snapshot.elements.count) elements")
    }
}

struct FindUIElementTool: Tool {
    let name = "find_ui_element"
    let description = "Finds controls in the front window whose title, description, value or placeholder contains the given text, optionally limited to a role such as AXButton, AXTextField, AXMenuItem, AXCheckBox. Returns matching elements with IDs."
    let parameters = [
        ToolParameterSpec.required("text", .string, "Text to look for, case-insensitive"),
        ToolParameterSpec.optional("role", .string, "Accessibility role to restrict to, for example AXButton"),
    ]
    let risk = RiskLevel.low
    let symbol = "scope"
    let context: AutomationContext

    func activityLabel(for arguments: ToolArguments) -> String {
        "Looking for \((try? arguments.string("text")) ?? "a control")"
    }
    func confirmationText(for arguments: ToolArguments) -> String { "Search the window for a control?" }

    func execute(_ arguments: ToolArguments, context toolContext: ToolContext) async throws -> ToolResult {
        let needle = try arguments.string("text").lowercased()
        let role = try arguments.optionalString("role")
        let app = try context.targetApp()
        let snapshot = try context.inspector.inspect(app: app, maxDepth: 25, maxElements: 800)
        let matches = snapshot.elements.filter { element in
            if let role, element.role != role { return false }
            return [element.title, element.description, element.value, element.placeholder]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(needle) }
        }
        guard !matches.isEmpty else {
            return ToolResult(content: "No element matches \"\(needle)\"\(role.map { " with role \($0)" } ?? "").", summary: "No match for \(needle)")
        }
        let listing = matches.prefix(25).map { $0.line.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        return ToolResult(content: listing, summary: "Found \(matches.count) matching element\(matches.count == 1 ? "" : "s")")
    }
}

struct PerformUIActionTool: Tool {
    let name = "perform_ui_action"
    let description = "Performs an Accessibility action on an element from the latest inspection: AXPress (click a button, menu item or checkbox), AXShowMenu, AXIncrement, AXDecrement, AXConfirm, AXCancel, AXRaise."
    let parameters = [
        ToolParameterSpec.required("element_id", .string, "The element ID, for example e7"),
        ToolParameterSpec.optional("action", .string, "The action name (default AXPress)"),
    ]
    let risk = RiskLevel.medium
    let symbol = "cursorarrow.click"
    let context: AutomationContext

    func activityLabel(for arguments: ToolArguments) -> String {
        "Pressing \(Self.describe(arguments, context: context))"
    }

    func confirmationText(for arguments: ToolArguments) -> String {
        let action = (try? arguments.optionalString("action")) ?? nil
        return "\(action == nil || action == "AXPress" ? "Press" : "Perform \(action!) on") \(Self.describe(arguments, context: context))?"
    }

    private static func describe(_ arguments: ToolArguments, context: AutomationContext) -> String {
        guard let id = try? arguments.string("element_id") else { return "an element" }
        guard let element = context.inspector.latestSnapshot?.element(withID: id) else { return "element \(id)" }
        let label = element.title ?? element.description ?? element.value ?? id
        return "\"\(label)\" (\(element.role))"
    }

    func execute(_ arguments: ToolArguments, context toolContext: ToolContext) async throws -> ToolResult {
        let id = try arguments.string("element_id")
        let action = try arguments.optionalString("action") ?? "AXPress"
        let label = Self.describe(arguments, context: context)
        try context.inspector.perform(action: action, on: id)
        return ToolResult(content: "\(action) performed on \(label). Inspect the window again to see the result.", summary: "Pressed \(label)")
    }
}

struct SetUIValueTool: Tool {
    let name = "set_ui_value"
    let description = "Sets the value of a text field, text area, slider, combo box or similar element from the latest inspection. Prefer this over typing."
    let parameters = [
        ToolParameterSpec.required("element_id", .string, "The element ID"),
        ToolParameterSpec.required("value", .string, "The new value"),
    ]
    let risk = RiskLevel.medium
    let symbol = "character.cursor.ibeam"
    let context: AutomationContext

    func activityLabel(for arguments: ToolArguments) -> String { "Entering text" }

    func confirmationText(for arguments: ToolArguments) -> String {
        let value = (try? arguments.string("value")) ?? ""
        let preview = value.count > 60 ? String(value.prefix(60)) + "…" : value
        let id = (try? arguments.string("element_id")) ?? "the field"
        let label = context.inspector.latestSnapshot?.element(withID: id).map { $0.title ?? $0.placeholder ?? $0.role } ?? id
        return "Set \"\(label)\" to \"\(preview)\"?"
    }

    func execute(_ arguments: ToolArguments, context toolContext: ToolContext) async throws -> ToolResult {
        let id = try arguments.string("element_id")
        let value = try arguments.string("value")
        try context.inspector.setValue(value, on: id)
        return ToolResult(content: "Value set on \(id). Inspect again to confirm.", summary: "Entered \(value.count) characters")
    }
}

struct FocusElementTool: Tool {
    let name = "focus_element"
    let description = "Gives keyboard focus to an element from the latest inspection and brings its window forward."
    let parameters = [ToolParameterSpec.required("element_id", .string, "The element ID")]
    let risk = RiskLevel.low
    let symbol = "target"
    let context: AutomationContext

    func activityLabel(for arguments: ToolArguments) -> String { "Focusing a control" }
    func confirmationText(for arguments: ToolArguments) -> String { "Focus element \((try? arguments.string("element_id")) ?? "")?" }

    func execute(_ arguments: ToolArguments, context toolContext: ToolContext) async throws -> ToolResult {
        let id = try arguments.string("element_id")
        try context.inspector.focus(id)
        return ToolResult(content: "Element \(id) is focused.", summary: "Focused \(id)")
    }
}

struct PressKeyTool: Tool {
    let name = "press_key"
    let description = "Sends a key press to the app the user is using, such as return, tab, escape, cmd+s, cmd+shift+t, ctrl+left. Use set_ui_value to enter text instead of typing letters one by one."
    let parameters = [ToolParameterSpec.required("keys", .string, "Key or chord, modifiers joined with +")]
    let risk = RiskLevel.medium
    let symbol = "keyboard"
    let context: AutomationContext

    func activityLabel(for arguments: ToolArguments) -> String { "Pressing \((try? arguments.string("keys")) ?? "a key")" }
    func confirmationText(for arguments: ToolArguments) -> String {
        "Press \((try? arguments.string("keys")) ?? "the key") in \((try? context.targetApp().localizedName) ?? "the front app")?"
    }

    func execute(_ arguments: ToolArguments, context toolContext: ToolContext) async throws -> ToolResult {
        let chord = try InputSynthesizer.parse(try arguments.string("keys"))
        let app = try context.targetApp()
        guard AXIsProcessTrusted() else { throw AutomationError.accessibilityNotGranted(appName: app.localizedName ?? "the app") }
        app.activate()
        try await Task.sleep(for: .milliseconds(120))
        InputSynthesizer.press(chord, to: app.processIdentifier)
        return ToolResult(content: "Pressed \(try arguments.string("keys")) in \(app.localizedName ?? "the app").", summary: "Pressed \(try arguments.string("keys"))")
    }
}

struct ScrollTool: Tool {
    let name = "scroll"
    let description = "Scrolls inside an element from the latest inspection, or in the middle of the front window. Positive lines scroll down."
    let parameters = [
        ToolParameterSpec.optional("element_id", .string, "Element to scroll within"),
        ToolParameterSpec.optional("lines", .integer, "Lines to scroll, negative for up (default 5)"),
    ]
    let risk = RiskLevel.low
    let symbol = "arrow.up.and.down"
    let context: AutomationContext

    func activityLabel(for arguments: ToolArguments) -> String { "Scrolling" }
    func confirmationText(for arguments: ToolArguments) -> String { "Scroll the window?" }

    func execute(_ arguments: ToolArguments, context toolContext: ToolContext) async throws -> ToolResult {
        let lines = try arguments.optionalInteger("lines") ?? 5
        let app = try context.targetApp()
        guard AXIsProcessTrusted() else { throw AutomationError.accessibilityNotGranted(appName: app.localizedName ?? "the app") }
        let frame: CGRect
        if let id = try arguments.optionalString("element_id"), let elementFrame = try context.inspector.frame(of: id) {
            frame = elementFrame
        } else {
            let snapshot = try context.inspector.inspect(app: app, maxDepth: 1, maxElements: 1)
            guard let windowFrame = snapshot.elements.first?.frame else { throw AutomationError.noWindow(appName: snapshot.appName) }
            frame = windowFrame
        }
        InputSynthesizer.scroll(lines: lines, at: CGPoint(x: frame.midX, y: frame.midY))
        return ToolResult(content: "Scrolled \(lines) lines.", summary: "Scrolled \(lines > 0 ? "down" : "up")")
    }
}

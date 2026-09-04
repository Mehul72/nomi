import CoreGraphics
import Foundation

/// A control as the model sees it: a short-lived ID plus the attributes that identify it semantically.
nonisolated struct UIElementSnapshot: Sendable, Equatable, Identifiable {
    var id: String
    var role: String
    var subrole: String?
    var title: String?
    var description: String?
    var value: String?
    var placeholder: String?
    var isEnabled: Bool
    var isFocused: Bool
    var frame: CGRect?
    var parentID: String?
    var depth: Int
    var actions: [String]
    var childCount: Int

    /// One dense line per element, the format that goes into the model's context.
    var line: String {
        var parts = ["[\(id)]", role]
        if let subrole, !subrole.isEmpty { parts.append("(\(subrole))") }
        if let title, !title.isEmpty { parts.append("title=\"\(Self.clip(title))\"") }
        if let description, !description.isEmpty { parts.append("desc=\"\(Self.clip(description))\"") }
        if let value, !value.isEmpty { parts.append("value=\"\(Self.clip(value))\"") }
        if let placeholder, !placeholder.isEmpty { parts.append("placeholder=\"\(Self.clip(placeholder))\"") }
        if !isEnabled { parts.append("disabled") }
        if isFocused { parts.append("focused") }
        if childCount > 0 { parts.append("children=\(childCount)") }
        if !actions.isEmpty { parts.append("actions=\(actions.joined(separator: ","))") }
        return String(repeating: "  ", count: depth) + parts.joined(separator: " ")
    }

    private static func clip(_ text: String, limit: Int = 80) -> String {
        let single = text.replacingOccurrences(of: "\n", with: " ")
        return single.count > limit ? String(single.prefix(limit)) + "…" : single
    }
}

/// Everything read from one application's Accessibility tree in one pass.
nonisolated struct UISnapshot: Sendable {
    var appName: String
    var bundleID: String
    var windowTitle: String?
    var elements: [UIElementSnapshot]
    var wasTruncated: Bool

    var text: String {
        var lines = ["App: \(appName) (\(bundleID))"]
        if let windowTitle { lines.append("Window: \(windowTitle)") }
        lines += elements.map(\.line)
        if wasTruncated { lines.append("[more elements not shown; inspect a specific element to go deeper]") }
        return lines.joined(separator: "\n")
    }

    func element(withID id: String) -> UIElementSnapshot? {
        elements.first { $0.id == id }
    }
}

nonisolated enum AutomationError: LocalizedError, Equatable {
    case accessibilityNotGranted(appName: String)
    case noFrontmostApp
    case noWindow(appName: String)
    case elementNotFound(String)
    case staleElement(String)
    case actionUnsupported(String, element: String)
    case actionFailed(String, code: Int32)
    case valueNotSettable(String)
    case unknownKey(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted(let appName):
            "I can see \(appName), but macOS has not granted Accessibility permission yet. Turn it on in System Settings > Privacy & Security > Accessibility."
        case .noFrontmostApp:
            "No application is in front."
        case .noWindow(let appName):
            "\(appName) has no window open to inspect."
        case .elementNotFound(let id):
            "There is no element \(id) in the latest inspection. Inspect the UI again to get fresh IDs."
        case .staleElement(let id):
            "Element \(id) is no longer on screen. Inspect the UI again."
        case .actionUnsupported(let action, let element):
            "Element \(element) does not support the action \(action)."
        case .actionFailed(let action, let code):
            "The action \(action) failed (Accessibility error \(code))."
        case .valueNotSettable(let id):
            "The value of element \(id) cannot be changed directly."
        case .unknownKey(let key):
            "Unknown key \(key)."
        }
    }
}

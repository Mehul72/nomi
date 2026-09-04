import AppKit
import ApplicationServices
import Foundation

/// Reads and drives other applications through the Accessibility API.
///
/// Every inspection produces short IDs (`e1`, `e2`, …) that map to live `AXUIElement` references
/// for the following actions. IDs are only valid until the next inspection.
final class AccessibilityInspector: @unchecked Sendable {
    static let maxDepth = 12
    static let maxElements = 160
    private static let secureRoles: Set<String> = ["AXSecureTextField"]
    /// Containers that add nothing the model can act on; their children are still visited.
    private static let transparentRoles: Set<String> = ["AXGroup", "AXSplitGroup", "AXScrollArea", "AXLayoutArea", "AXLayoutItem", "AXUnknown"]

    private let lock = NSLock()
    private var elementsByID: [String: AXUIElement] = [:]
    private var lastSnapshot: UISnapshot?

    // MARK: Inspection

    func inspect(app: NSRunningApplication, root rootID: String? = nil, maxDepth: Int = maxDepth, maxElements: Int = maxElements) throws -> UISnapshot {
        guard AXIsProcessTrusted() else {
            throw AutomationError.accessibilityNotGranted(appName: app.localizedName ?? "the app")
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 2)

        let root: AXUIElement
        var windowTitle: String?
        if let rootID {
            root = try element(for: rootID)
        } else {
            guard let window = Self.focusedWindow(of: application) else {
                throw AutomationError.noWindow(appName: app.localizedName ?? "The app")
            }
            root = window
            windowTitle = Self.string(window, kAXTitleAttribute)
        }

        var elements: [UIElementSnapshot] = []
        var table: [String: AXUIElement] = [:]
        var truncated = false
        var queue: [(element: AXUIElement, depth: Int, parentID: String?)] = [(root, 0, nil)]
        while !queue.isEmpty {
            let (element, depth, parentID) = queue.removeFirst()
            if elements.count >= maxElements {
                truncated = true
                break
            }
            let role = Self.string(element, kAXRoleAttribute) ?? "AXUnknown"
            let children = depth < maxDepth ? Self.children(of: element) : []
            let isTransparent = Self.transparentRoles.contains(role) && depth > 0
            var ownID = parentID
            if !isTransparent {
                let id = "e\(elements.count + 1)"
                table[id] = element
                elements.append(Self.snapshot(of: element, role: role, id: id, parentID: parentID, depth: depth, childCount: children.count))
                ownID = id
            } else if depth >= maxDepth {
                truncated = true
            }
            queue.append(contentsOf: children.map { ($0, depth + 1, ownID) })
        }

        let snapshot = UISnapshot(
            appName: app.localizedName ?? "Unknown",
            bundleID: app.bundleIdentifier ?? "unknown",
            windowTitle: windowTitle,
            elements: elements,
            wasTruncated: truncated
        )
        lock.withLock {
            elementsByID = table
            lastSnapshot = snapshot
        }
        return snapshot
    }

    var latestSnapshot: UISnapshot? {
        lock.withLock { lastSnapshot }
    }

    /// Text the front window exposes, in reading order, for screen questions.
    func readableText(app: NSRunningApplication, maxCharacters: Int = 12_000) throws -> String {
        let snapshot = try inspect(app: app, maxDepth: 20, maxElements: 600)
        var pieces: [String] = []
        var total = 0
        for element in snapshot.elements {
            for candidate in [element.title, element.value, element.description] {
                guard let candidate, !candidate.isEmpty, !pieces.contains(candidate) else { continue }
                pieces.append(candidate)
                total += candidate.count
                if total >= maxCharacters { return pieces.joined(separator: "\n") }
            }
        }
        return pieces.joined(separator: "\n")
    }

    // MARK: Actions

    func perform(action: String, on id: String) throws {
        let element = try element(for: id)
        let actions = Self.actions(of: element)
        guard actions.contains(action) else {
            throw AutomationError.actionUnsupported(action, element: id)
        }
        let result = AXUIElementPerformAction(element, action as CFString)
        try Self.check(result, action: action, id: id)
    }

    func setValue(_ value: String, on id: String) throws {
        let element = try element(for: id)
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        guard settable.boolValue else { throw AutomationError.valueNotSettable(id) }
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
        try Self.check(result, action: "set value", id: id)
    }

    func focus(_ id: String) throws {
        let element = try element(for: id)
        if let window = Self.window(containing: element) {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        let result = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try Self.check(result, action: "focus", id: id)
    }

    func frame(of id: String) throws -> CGRect? {
        Self.frame(of: try element(for: id))
    }

    private func element(for id: String) throws -> AXUIElement {
        guard let element = lock.withLock({ elementsByID[id] }) else {
            throw AutomationError.elementNotFound(id)
        }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success else {
            throw AutomationError.staleElement(id)
        }
        return element
    }

    private static func check(_ result: AXError, action: String, id: String) throws {
        switch result {
        case .success: return
        case .invalidUIElement: throw AutomationError.staleElement(id)
        case .actionUnsupported: throw AutomationError.actionUnsupported(action, element: id)
        default: throw AutomationError.actionFailed(action, code: result.rawValue)
        }
    }

    // MARK: Attribute reading

    private static func snapshot(of element: AXUIElement, role: String, id: String, parentID: String?, depth: Int, childCount: Int) -> UIElementSnapshot {
        let isSecure = secureRoles.contains(role)
        var value: String?
        if !isSecure, let raw = attribute(element, kAXValueAttribute) {
            value = describe(raw)
        }
        return UIElementSnapshot(
            id: id,
            role: role,
            subrole: string(element, kAXSubroleAttribute),
            title: string(element, kAXTitleAttribute),
            description: string(element, kAXDescriptionAttribute) ?? string(element, kAXHelpAttribute),
            value: value,
            placeholder: string(element, kAXPlaceholderValueAttribute),
            isEnabled: bool(element, kAXEnabledAttribute) ?? true,
            isFocused: bool(element, kAXFocusedAttribute) ?? false,
            frame: frame(of: element),
            parentID: parentID,
            depth: depth,
            actions: actions(of: element).filter { $0 != "AXScrollToVisible" },
            childCount: childCount
        )
    }

    private static func focusedWindow(of application: AXUIElement) -> AXUIElement? {
        if let focused = attribute(application, kAXFocusedWindowAttribute) {
            return (focused as! AXUIElement)
        }
        if let main = attribute(application, kAXMainWindowAttribute) {
            return (main as! AXUIElement)
        }
        return children(of: application, attribute: kAXWindowsAttribute).first
    }

    private static func window(containing element: AXUIElement) -> AXUIElement? {
        if let window = attribute(element, kAXWindowAttribute) {
            return (window as! AXUIElement)
        }
        return nil
    }

    static func children(of element: AXUIElement, attribute name: String = kAXChildrenAttribute) -> [AXUIElement] {
        guard let value = attribute(element, name) else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    static func actions(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success, let names = names as? [String] else { return [] }
        return names
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        guard let value = attribute(element, name) else { return nil }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        guard let value = attribute(element, name) else { return nil }
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute), let sizeValue = attribute(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position), AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Values can be strings, numbers, booleans or attributed strings; anything else is summarised by type.
    private static func describe(_ value: CFTypeRef) -> String? {
        switch value {
        case let string as String: return string
        case let attributed as NSAttributedString: return attributed.string
        case let number as NSNumber: return number.stringValue
        case let url as URL: return url.absoluteString
        default: return nil
        }
    }
}

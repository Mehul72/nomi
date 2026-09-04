import AppKit
import Foundation
import UserNotifications

struct CurrentTimeTool: Tool {
    let name = "get_current_time"
    let description = "Returns the current date, time, weekday and time zone on this Mac."
    let parameters: [ToolParameterSpec] = []
    let risk = RiskLevel.low
    let symbol = "clock"

    func activityLabel(for arguments: ToolArguments) -> String { "Checking the time" }
    func confirmationText(for arguments: ToolArguments) -> String { "Read the current time?" }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .long
        return ToolResult(content: "\(formatter.string(from: now)) (ISO 8601: \(now.ISO8601Format()))", summary: "Read the current time")
    }
}

struct FrontmostAppTool: Tool {
    let name = "get_frontmost_app"
    let description = "Returns the name and bundle identifier of the application the user is currently using."
    let parameters: [ToolParameterSpec] = []
    let risk = RiskLevel.low
    let symbol = "macwindow"

    func activityLabel(for arguments: ToolArguments) -> String { "Checking the current app" }
    func confirmationText(for arguments: ToolArguments) -> String { "Read which app is in front?" }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let app = await MainActor.run { RunningApps.frontmost() }
        guard let app else { return ToolResult(content: "No application is in front.", summary: "No app in front") }
        return ToolResult(content: "\(app.name) (\(app.bundleID))", summary: "Current app: \(app.name)")
    }
}

struct RunningAppsTool: Tool {
    let name = "list_running_apps"
    let description = "Lists the applications currently running with a user interface."
    let parameters: [ToolParameterSpec] = []
    let risk = RiskLevel.low
    let symbol = "square.stack"

    func activityLabel(for arguments: ToolArguments) -> String { "Listing running apps" }
    func confirmationText(for arguments: ToolArguments) -> String { "List the running apps?" }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let apps = await MainActor.run { RunningApps.visible() }
        let lines = apps.map { "\($0.name) (\($0.bundleID))" }
        return ToolResult(content: lines.joined(separator: "\n"), summary: "\(apps.count) apps running")
    }
}

struct OpenAppTool: Tool {
    let name = "open_app"
    let description = "Opens an application by name (for example Calendar, Safari, Microsoft Excel) or bundle identifier and brings it to the front."
    let parameters = [ToolParameterSpec.required("name", .string, "Application name or bundle identifier")]
    let risk = RiskLevel.low
    let symbol = "arrow.up.forward.app"

    func activityLabel(for arguments: ToolArguments) -> String {
        "Opening \((try? arguments.string("name")) ?? "app")"
    }

    func confirmationText(for arguments: ToolArguments) -> String {
        "Open \((try? arguments.string("name")) ?? "the app")?"
    }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let requested = try arguments.string("name")
        guard let url = await MainActor.run(body: { RunningApps.applicationURL(matching: requested) }) else {
            throw ToolError.failed("No application called \(requested) is installed.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        let name = app.localizedName ?? requested
        return ToolResult(content: "Opened \(name) (\(app.bundleIdentifier ?? "unknown bundle")).", summary: "Opened \(name)")
    }
}

struct OpenURLTool: Tool {
    let name = "open_url"
    let description = "Opens a web address in the default browser. Only http and https addresses are allowed."
    let parameters = [ToolParameterSpec.required("url", .string, "The full address, starting with http:// or https://")]
    let risk = RiskLevel.medium
    let symbol = "safari"

    func activityLabel(for arguments: ToolArguments) -> String { "Opening a web page" }

    func confirmationText(for arguments: ToolArguments) -> String {
        "Open \((try? arguments.string("url")) ?? "this address") in your browser?"
    }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let text = try arguments.string("url")
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil else {
            throw ToolError.invalidArgument(name: "url", reason: "must be an http or https address")
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else { throw ToolError.failed("The browser did not open the address.") }
        return ToolResult(content: "Opened \(url.absoluteString) in the default browser.", summary: "Opened \(url.host() ?? "page")")
    }
}

struct ShowNotificationTool: Tool {
    let name = "show_notification"
    let description = "Shows a macOS notification with a title and short message."
    let parameters = [
        ToolParameterSpec.required("title", .string, "Notification title"),
        ToolParameterSpec.required("message", .string, "Notification body, one or two sentences"),
    ]
    let risk = RiskLevel.low
    let symbol = "bell"

    func activityLabel(for arguments: ToolArguments) -> String { "Showing a notification" }
    func confirmationText(for arguments: ToolArguments) -> String {
        "Show a notification titled \"\((try? arguments.string("title")) ?? "")\"?"
    }

    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        let title = try arguments.string("title")
        let message = try arguments.string("message")
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else {
            throw ToolError.notPermitted("Notifications are turned off for Nomi in System Settings > Notifications.")
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        return ToolResult(content: "Notification shown.", summary: "Showed a notification")
    }
}

/// Application lookups shared by the system tools.
enum RunningApps {
    struct Entry: Sendable {
        let name: String
        let bundleID: String
    }

    /// The app the user is working in. Nomi itself never counts, even when a URL command activated it.
    static func frontmost() -> Entry? {
        FrontmostAppTracker.shared.current.flatMap(entry)
    }

    static func visible() -> [Entry] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(entry)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func entry(_ app: NSRunningApplication) -> Entry? {
        guard let name = app.localizedName, let bundleID = app.bundleIdentifier else { return nil }
        return Entry(name: name, bundleID: bundleID)
    }

    /// Finds an app by bundle identifier, then by exact or prefix name in the usual application folders.
    static func applicationURL(matching requested: String) -> URL? {
        let workspace = NSWorkspace.shared
        if requested.contains("."), let url = workspace.urlForApplication(withBundleIdentifier: requested) {
            return url
        }
        if let running = workspace.runningApplications.first(where: { $0.localizedName?.caseInsensitiveCompare(requested) == .orderedSame }),
           let url = running.bundleURL {
            return url
        }
        let folders = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
        ]
        var candidates: [URL] = []
        for folder in folders {
            let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            candidates += contents.filter { $0.pathExtension == "app" }
        }
        let wanted = requested.lowercased()
        if let exact = candidates.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == wanted }) {
            return exact
        }
        return candidates.first { $0.deletingPathExtension().lastPathComponent.lowercased().contains(wanted) }
    }
}

/// Remembers the most recently activated app other than Nomi.
final class FrontmostAppTracker {
    static let shared = FrontmostAppTracker()
    private(set) var current: NSRunningApplication?

    private init() {
        let workspace = NSWorkspace.shared
        if let front = workspace.frontmostApplication, front != .current {
            current = front
        }
        workspace.notificationCenter.addObserver(
            self, selector: #selector(activated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
    }

    /// Creating the singleton early means the first question already knows the previous app.
    static func start() {
        _ = shared
    }

    @objc private func activated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app != NSRunningApplication.current else { return }
        current = app
    }
}

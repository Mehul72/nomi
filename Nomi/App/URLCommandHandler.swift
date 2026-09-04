import AppKit

/// Commands reachable through `nomi://` URLs, so scripts and Shortcuts can drive the surface.
enum URLCommand: Equatable {
    case open
    case close
    case toggle
    case welcome
    case settings(SettingsSection?)
    /// `nomi://ask?q=What%20time%20is%20it` opens the surface and asks.
    case ask(String)
    #if DEBUG
    /// Logs which window would receive a click beside the surface, to confirm transparent pixels pass clicks through.
    case probe
    /// Closes the Settings and Welcome windows so scripted checks never send ⌘W to another app.
    case closewindows
    /// Starts downloading, or loading, the selected model without clicking through Settings.
    case download(String?)
    case load
    case verify(String?)
    /// Runs the vision model on an image file and logs the description, so the swap and unload path can be checked
    /// without Screen Recording permission.
    case describe(String)
    #endif

    init?(url: URL) {
        guard let host = url.host() else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        switch host {
        case "open": self = .open
        case "close": self = .close
        case "toggle": self = .toggle
        case "welcome": self = .welcome
        case "settings": self = .settings(value("section").flatMap(SettingsSection.init(rawValue:)))
        case "ask":
            guard let question = value("q"), !question.isEmpty else { return nil }
            self = .ask(question)
        #if DEBUG
        case "probe": self = .probe
        case "closewindows": self = .closewindows
        case "download": self = .download(value("id"))
        case "load": self = .load
        case "verify": self = .verify(value("id"))
        case "describe":
            guard let path = value("path"), !path.isEmpty else { return nil }
            self = .describe(path)
        #endif
        default: return nil
        }
    }
}

final class URLCommandHandler {
    private let perform: (URLCommand) -> Void

    init(perform: @escaping (URLCommand) -> Void) {
        self.perform = perform
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard
            let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: string),
            let command = URLCommand(url: url)
        else {
            Log.app.notice("Ignored URL command")
            return
        }
        perform(command)
    }
}

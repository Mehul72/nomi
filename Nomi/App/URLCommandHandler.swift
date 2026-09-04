import AppKit

/// Commands reachable through `nomi://` URLs, so scripts and Shortcuts can drive the surface.
enum URLCommand: String {
    case open
    case close
    case toggle
    case welcome
    case settings
    #if DEBUG
    /// Logs which window would receive a click beside the surface, to confirm transparent pixels pass clicks through.
    case probe
    /// Closes the Settings and Welcome windows so scripted checks never send ⌘W to another app.
    case closewindows
    #endif
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
            let host = url.host(),
            let command = URLCommand(rawValue: host)
        else { return }
        perform(command)
    }
}

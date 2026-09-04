import AppKit

// AppKit owns the lifecycle: every window here is an NSWindow or NSPanel hosting SwiftUI content.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

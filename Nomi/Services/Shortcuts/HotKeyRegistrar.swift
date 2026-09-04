import AppKit
import Carbon.HIToolbox

/// Registers one system-wide shortcut through Carbon, which needs no Accessibility or Input Monitoring permission.
final class HotKeyRegistrar {
    private(set) var shortcut: KeyboardShortcut?
    private let onPress: () -> Void
    // Carbon handles are plain pointers; deinit must be able to release them without an actor hop.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var handlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x4E4F4D49), id: 1) // "NOMI"

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        installHandler()
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    enum RegistrationError: Error {
        case notUsableGlobally
        case rejected(OSStatus)
    }

    func register(_ shortcut: KeyboardShortcut) throws(RegistrationError) {
        guard shortcut.isUsableGlobally else { throw .notUsableGlobally }
        unregister()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), shortcut.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { throw .rejected(status) }
        hotKeyRef = ref
        self.shortcut = shortcut
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        shortcut = nil
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, selfPointer, &handlerRef)
    }

    fileprivate func handlePress() {
        onPress()
    }
}

/// Carbon calls this on the main thread for every registered hot key press.
private let hotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var pressed = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
    )
    guard status == noErr else { return status }
    let registrar = Unmanaged<HotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        registrar.handlePress()
    }
    return noErr
}

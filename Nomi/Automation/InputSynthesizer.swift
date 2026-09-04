import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Keyboard and scroll events for the cases the Accessibility API cannot express. Clicks by coordinate are the last resort.
nonisolated enum InputSynthesizer {
    static let keyNames: [String: Int] = [
        "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "space": kVK_Space, "escape": kVK_Escape, "esc": kVK_Escape,
        "delete": kVK_Delete, "backspace": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
        "up": kVK_UpArrow, "down": kVK_DownArrow, "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G,
        "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N,
        "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U,
        "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
        ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, "`": kVK_ANSI_Grave,
    ]

    nonisolated struct KeyChord: Equatable, Sendable {
        var keyCode: CGKeyCode
        var flags: CGEventFlags
    }

    /// Parses `cmd+shift+s`, `return`, `ctrl+left` and similar.
    static func parse(_ chord: String) throws -> KeyChord {
        let parts = chord.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, !last.isEmpty else { throw AutomationError.unknownKey(chord) }
        var flags: CGEventFlags = []
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "alt", "option", "opt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default: throw AutomationError.unknownKey(chord)
            }
        }
        guard let code = keyNames[last] else { throw AutomationError.unknownKey(chord) }
        return KeyChord(keyCode: CGKeyCode(code), flags: flags)
    }

    static func press(_ chord: KeyChord, to pid: pid_t?) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: chord.keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: chord.keyCode, keyDown: false)
        down?.flags = chord.flags
        up?.flags = chord.flags
        if let pid {
            down?.postToPid(pid)
            up?.postToPid(pid)
        } else {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Scrolls at a screen point (top-left origin). Positive `lines` scrolls down.
    static func scroll(lines: Int, at point: CGPoint) {
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(-lines), wheel2: 0, wheel3: 0)
        event?.location = point
        event?.post(tap: .cghidEventTap)
    }

    static func click(at point: CGPoint) {
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
        usleep(30_000)
        down?.post(tap: .cghidEventTap)
        usleep(40_000)
        up?.post(tap: .cghidEventTap)
    }
}

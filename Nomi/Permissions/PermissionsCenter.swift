import AppKit
import ApplicationServices
import AVFoundation
import CoreLocation
import EventKit
import Foundation
import Observation
import Speech

/// One permission macOS controls, with the real state read from the system each time it is refreshed.
nonisolated enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case accessibility, screenRecording, microphone, speechRecognition, location, calendar, reminders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .microphone: "Microphone"
        case .speechRecognition: "Speech Recognition"
        case .location: "Location"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        }
    }

    var reason: String {
        switch self {
        case .accessibility: "Lets Nomi read and operate the controls of other apps, which every automation task needs."
        case .screenRecording: "Lets Nomi capture the front window when you ask what is on your screen."
        case .microphone: "Lets you ask questions by voice."
        case .speechRecognition: "Turns your voice into text, on this Mac when the language supports it."
        case .location: "Answers weather questions when no home location is set."
        case .calendar: "Lets Nomi list and create events when you ask."
        case .reminders: "Lets Nomi create reminders when you ask."
        }
    }

    /// The System Settings pane where the user can change the permission.
    var settingsURL: URL {
        let pane: String
        switch self {
        case .accessibility: pane = "Privacy_Accessibility"
        case .screenRecording: pane = "Privacy_ScreenCapture"
        case .microphone: pane = "Privacy_Microphone"
        case .speechRecognition: pane = "Privacy_SpeechRecognition"
        case .location: pane = "Privacy_LocationServices"
        case .calendar: pane = "Privacy_Calendars"
        case .reminders: pane = "Privacy_Reminders"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }
}

nonisolated enum PermissionState: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    case restricted

    var text: String {
        switch self {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not asked yet"
        case .restricted: "Restricted"
        }
    }
}

/// Reads and requests the permissions the assistant depends on. States are real, never cached guesses.
@Observable
final class PermissionsCenter {
    private(set) var states: [PermissionKind: PermissionState] = [:]
    private var locationManager: CLLocationManager?

    init() {
        refresh()
    }

    func state(of kind: PermissionKind) -> PermissionState {
        states[kind] ?? .notDetermined
    }

    func refresh() {
        for kind in PermissionKind.allCases {
            states[kind] = Self.read(kind)
        }
    }

    static func read(_ kind: PermissionKind) -> PermissionState {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .microphone:
            return map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .speechRecognition:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        case .location:
            switch CLLocationManager().authorizationStatus {
            case .authorizedAlways, .authorized: return .granted
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        case .calendar:
            return map(EKEventStore.authorizationStatus(for: .event))
        case .reminders:
            return map(EKEventStore.authorizationStatus(for: .reminder))
        }
    }

    /// Asks macOS for the permission where an API exists, otherwise opens the right System Settings pane.
    func request(_ kind: PermissionKind) async {
        switch kind {
        case .accessibility:
            // The constant's value is the string "AXTrustedCheckOptionPrompt"; spelling it out avoids a non-Sendable global.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) {
                NSWorkspace.shared.open(kind.settingsURL)
            }
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() {
                NSWorkspace.shared.open(kind.settingsURL)
            }
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .speechRecognition:
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        case .location:
            let manager = locationManager ?? CLLocationManager()
            locationManager = manager
            manager.requestWhenInUseAuthorization()
        case .calendar:
            _ = try? await EKEventStore().requestFullAccessToEvents()
        case .reminders:
            _ = try? await EKEventStore().requestFullAccessToReminders()
        }
        refresh()
    }

    func openSystemSettings(for kind: PermissionKind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private static func map(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess, .authorized: .granted
        case .writeOnly: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}

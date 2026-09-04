import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Captures one window through ScreenCaptureKit, only when a request needs it. Nothing is recorded continuously.
nonisolated enum ScreenCapture {
    nonisolated struct WindowImage: @unchecked Sendable {
        let image: CGImage
        /// Window frame in screen points, top-left origin, so recognised text can be mapped back to the screen.
        let frame: CGRect
        let title: String?
        let appName: String
    }

    enum CaptureError: LocalizedError {
        case permissionDenied
        case noWindow(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "Screen Recording permission is off, so Nomi cannot capture the window. Turn it on in System Settings > Privacy & Security > Screen Recording."
            case .noWindow(let app):
                "\(app) has no window on screen to capture."
            }
        }
    }

    /// The front window of the given app, at native resolution, without the cursor.
    static func captureFrontWindow(of app: NSRunningApplication) async throws -> WindowImage {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let pid = app.processIdentifier
        let candidates = content.windows
            .filter { $0.owningApplication?.processID == pid && $0.isOnScreen && $0.windowLayer == 0 && $0.frame.width > 50 && $0.frame.height > 50 }
        guard let window = candidates.first else {
            throw CaptureError.noWindow(app.localizedName ?? "The app")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = NSScreen.screens.first { $0.frame.intersects(Self.appKitRect(window.frame)) }?.backingScaleFactor ?? 2
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return WindowImage(image: image, frame: window.frame, title: window.title, appName: app.localizedName ?? "Unknown")
    }

    /// SCWindow frames use a top-left origin; NSScreen frames use bottom-left. Both are needed to pick the display.
    private static func appKitRect(_ rect: CGRect) -> CGRect {
        guard let main = NSScreen.screens.first else { return rect }
        return CGRect(x: rect.minX, y: main.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

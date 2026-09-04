import AppKit

/// The few facts about a display that notch layout depends on, captured so layout is testable without an `NSScreen`.
nonisolated struct DisplayLayout: Equatable, Sendable {
    /// Full screen rectangle in AppKit coordinates (origin bottom-left).
    var frame: CGRect
    /// Screen minus menu bar and Dock.
    var visibleFrame: CGRect
    /// Height of the camera housing. Zero on displays without one.
    var safeAreaTop: CGFloat
    /// Unobscured strips either side of the housing. Empty on displays without one.
    var auxiliaryTopLeft: CGRect
    var auxiliaryTopRight: CGRect
    /// Backing scale, used to keep window origins on device pixels.
    var scale: CGFloat

    init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat, auxiliaryTopLeft: CGRect, auxiliaryTopRight: CGRect, scale: CGFloat = 2) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
        self.scale = scale
    }

    var hasHousing: Bool {
        safeAreaTop > 0 && !auxiliaryTopLeft.isEmpty && !auxiliaryTopRight.isEmpty
    }

    /// Menu bar height as reported by the visible frame, or a conventional value when the bar is hidden.
    var menuBarHeight: CGFloat {
        let reported = frame.maxY - visibleFrame.maxY
        return reported > 0 ? reported : 24
    }
}

extension DisplayLayout {
    @MainActor
    init(screen: NSScreen) {
        self.init(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea ?? .zero,
            auxiliaryTopRight: screen.auxiliaryTopRightArea ?? .zero,
            scale: screen.backingScaleFactor
        )
    }
}

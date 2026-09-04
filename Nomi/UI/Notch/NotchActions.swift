import Foundation

/// What the surface view can ask its controller to do.
struct NotchActions {
    var open: () -> Void
    var close: () -> Void
    var hoverChanged: (Bool) -> Void
    var submit: () -> Void
    var microphoneTapped: () -> Void
    var contentHeightChanged: (CGFloat) -> Void

    static let none = NotchActions(
        open: {}, close: {}, hoverChanged: { _ in }, submit: {}, microphoneTapped: {}, contentHeightChanged: { _ in }
    )
}

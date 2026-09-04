import SwiftUI

/// The visual constants from the design specification. Numbers live here so views do not invent their own.
nonisolated enum NotchStyle {
    static let surface = Color.black
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.6)
    static let tertiaryText = Color.white.opacity(0.38)
    static let fieldFill = Color.white.opacity(0.1)

    static let bottomCornerRadius: CGFloat = 24
    static let controlRadius: CGFloat = 8
    static let inset: CGFloat = 16
    static let rowSpacing: CGFloat = 8
    static let groupSpacing: CGFloat = 16
    static let fieldHeight: CGFloat = 32

    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 11)
    static let caption2 = Font.system(size: 10)

    static let openSpring = Spring(response: 0.42, dampingRatio: 0.86)
    static let hoverSpring = Spring(response: 0.28, dampingRatio: 0.9)
    static let contentFadeDuration: TimeInterval = 0.12
    static let reducedMotionDuration: TimeInterval = 0.15
    static let hoverDelay: TimeInterval = 0.15

    /// Time at which a spring from rest has covered the given fraction of its travel.
    static func travelTime(of spring: Spring, fraction: Double) -> TimeInterval {
        var time: TimeInterval = 0
        let step: TimeInterval = 1.0 / 240.0
        while time < spring.settlingDuration {
            if spring.value(target: 1.0, initialVelocity: 0, time: time) >= fraction { return time }
            time += step
        }
        return spring.settlingDuration
    }
}

/// The notch surface: flush with the screen edge on top, continuous curves on the two bottom corners.
struct NotchSurfaceShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: NotchStyle.bottomCornerRadius,
            bottomTrailingRadius: NotchStyle.bottomCornerRadius,
            topTrailingRadius: 0,
            style: .continuous
        ).path(in: rect)
    }
}

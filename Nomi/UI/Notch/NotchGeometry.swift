import CoreGraphics

nonisolated enum NotchState: Equatable, Sendable {
    case idle
    case hovering
    case open
}

/// Sizes and window frames for every notch state, derived from the display and never hard-coded.
nonisolated struct NotchGeometry: Equatable, Sendable {
    static let hoverGrowth: CGFloat = 4
    static let openExtraWidth: CGFloat = 160
    static let openMinWidth: CGFloat = 420
    static let openMaxWidth: CGFloat = 560
    static let openHeightFractionOfScreen: CGFloat = 0.4
    /// Width of the island drawn on displays that have no physical housing.
    static let islandWidth: CGFloat = 200

    let display: DisplayLayout
    /// The camera housing (or its stand-in island) in screen coordinates.
    let housing: CGRect

    init(display: DisplayLayout) {
        self.display = display
        if display.hasHousing {
            let left = display.auxiliaryTopLeft.maxX
            let right = display.auxiliaryTopRight.minX
            housing = CGRect(
                x: left,
                y: display.frame.maxY - display.safeAreaTop,
                width: right - left,
                height: display.safeAreaTop
            )
        } else {
            let height = display.menuBarHeight
            housing = CGRect(
                x: display.frame.midX - Self.islandWidth / 2,
                y: display.frame.maxY - height,
                width: Self.islandWidth,
                height: height
            )
        }
    }

    var idleSize: CGSize { housing.size }

    var hoverSize: CGSize {
        CGSize(width: housing.width + Self.hoverGrowth * 2, height: housing.height + Self.hoverGrowth)
    }

    var openWidth: CGFloat {
        min(max(housing.width + Self.openExtraWidth, Self.openMinWidth), Self.openMaxWidth)
    }

    var maxOpenHeight: CGFloat {
        (display.frame.height * Self.openHeightFractionOfScreen).rounded(.down)
    }

    func openSize(contentHeight: CGFloat) -> CGSize {
        let height = min(max(contentHeight, hoverSize.height), maxOpenHeight)
        return CGSize(width: openWidth, height: height)
    }

    func size(for state: NotchState, contentHeight: CGFloat) -> CGSize {
        switch state {
        case .idle: idleSize
        case .hovering: hoverSize
        case .open: openSize(contentHeight: contentHeight)
        }
    }

    /// Window frame for a surface of the given size: flush with the top edge, centred on the housing.
    func frame(for size: CGSize) -> CGRect {
        let scale = max(display.scale, 1)
        let x = ((housing.midX - size.width / 2) * scale).rounded() / scale
        return CGRect(
            x: x,
            y: display.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    func frame(for state: NotchState, contentHeight: CGFloat) -> CGRect {
        frame(for: size(for: state, contentHeight: contentHeight))
    }

    /// The largest window needed while the surface animates between two states.
    func transitionFrame(from: NotchState, to: NotchState, contentHeight: CGFloat) -> CGRect {
        let a = frame(for: from, contentHeight: contentHeight)
        let b = frame(for: to, contentHeight: contentHeight)
        return a.union(b)
    }

    /// Frame large enough for anything the open state can show, used while the content height is still unknown.
    var maximumFrame: CGRect {
        frame(for: CGSize(width: openWidth, height: maxOpenHeight))
    }
}

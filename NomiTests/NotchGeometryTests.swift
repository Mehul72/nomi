import CoreGraphics
import Testing
@testable import Nomi

struct NotchGeometryTests {
    /// The 14-inch MacBook Pro built-in display, values read from NSScreen on the development machine.
    static let notchedDisplay = DisplayLayout(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        safeAreaTop: 32,
        auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxiliaryTopRight: CGRect(x: 848, y: 950, width: 664, height: 32),
        scale: 2
    )

    /// A 4K external display at 2x, placed to the right of the built-in one.
    static let externalDisplay = DisplayLayout(
        frame: CGRect(x: 1512, y: -100, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1512, y: -100, width: 1920, height: 1055),
        safeAreaTop: 0,
        auxiliaryTopLeft: .zero,
        auxiliaryTopRight: .zero,
        scale: 2
    )

    @Test func housingMatchesTheGapBetweenAuxiliaryAreas() {
        let geometry = NotchGeometry(display: Self.notchedDisplay)
        #expect(geometry.housing == CGRect(x: 663, y: 950, width: 185, height: 32))
        #expect(geometry.idleSize == CGSize(width: 185, height: 32))
    }

    @Test func idleFrameIsExactlyTheHousing() {
        let geometry = NotchGeometry(display: Self.notchedDisplay)
        #expect(geometry.frame(for: .idle, contentHeight: 0) == geometry.housing)
    }

    @Test func hoverGrowsFourPointsEachSideAndDown() {
        let geometry = NotchGeometry(display: Self.notchedDisplay)
        let frame = geometry.frame(for: .hovering, contentHeight: 0)
        #expect(frame == CGRect(x: 659, y: 946, width: 193, height: 36))
        #expect(frame.maxY == Self.notchedDisplay.frame.maxY)
    }

    @Test func openWidthIsClampedToTheMinimum() {
        let geometry = NotchGeometry(display: Self.notchedDisplay)
        #expect(geometry.openWidth == 420)
        let frame = geometry.frame(for: .open, contentHeight: 120)
        #expect(frame == CGRect(x: 545.5, y: 862, width: 420, height: 120))
        #expect(frame.midX == geometry.housing.midX)
    }

    @Test func openWidthIsClampedToTheMaximum() {
        var wide = Self.notchedDisplay
        wide.auxiliaryTopLeft = CGRect(x: 0, y: 950, width: 500, height: 32)
        wide.auxiliaryTopRight = CGRect(x: 1012, y: 950, width: 500, height: 32)
        let geometry = NotchGeometry(display: wide)
        #expect(geometry.housing.width == 512)
        #expect(geometry.openWidth == 560)
    }

    @Test func openHeightIsCappedAtFortyPercentOfTheScreen() {
        let geometry = NotchGeometry(display: Self.notchedDisplay)
        #expect(geometry.maxOpenHeight == 392)
        #expect(geometry.openSize(contentHeight: 5000).height == 392)
        #expect(geometry.openSize(contentHeight: 0).height == geometry.hoverSize.height)
    }

    @Test func externalDisplayGetsACentredIslandTheHeightOfTheMenuBar() {
        let geometry = NotchGeometry(display: Self.externalDisplay)
        #expect(!Self.externalDisplay.hasHousing)
        #expect(geometry.housing == CGRect(x: 2372, y: 955, width: 200, height: 25))
        #expect(geometry.housing.midX == Self.externalDisplay.frame.midX)
        #expect(geometry.frame(for: .idle, contentHeight: 0).maxY == Self.externalDisplay.frame.maxY)
    }

    @Test func eachDisplayLaysOutIndependently() {
        let internalGeometry = NotchGeometry(display: Self.notchedDisplay)
        let externalGeometry = NotchGeometry(display: Self.externalDisplay)
        #expect(!internalGeometry.maximumFrame.intersects(externalGeometry.maximumFrame))
        #expect(Self.notchedDisplay.frame.contains(internalGeometry.maximumFrame))
        #expect(Self.externalDisplay.frame.contains(externalGeometry.maximumFrame))
    }

    @Test func resolutionChangeMovesTheHousingWithTheScreen() {
        var scaled = Self.notchedDisplay
        scaled.frame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        scaled.visibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        scaled.auxiliaryTopLeft = CGRect(x: 0, y: 1085, width: 758, height: 32)
        scaled.auxiliaryTopRight = CGRect(x: 970, y: 1085, width: 758, height: 32)
        let before = NotchGeometry(display: Self.notchedDisplay)
        let after = NotchGeometry(display: scaled)
        #expect(after.housing == CGRect(x: 758, y: 1085, width: 212, height: 32))
        #expect(after.maxOpenHeight == 446)
        #expect(after.frame(for: .idle, contentHeight: 0).maxY == 1117)
        #expect(before != after)
    }

    @Test func hiddenMenuBarStillGivesTheIslandAHeight() {
        var noMenuBar = Self.externalDisplay
        noMenuBar.visibleFrame = noMenuBar.frame
        #expect(noMenuBar.menuBarHeight == 24)
    }

    @Test func windowOriginsLandOnDevicePixels() {
        let geometry = NotchGeometry(display: Self.notchedDisplay)
        for state in [NotchState.idle, .hovering, .open] {
            let x = geometry.frame(for: state, contentHeight: 100).minX
            #expect((x * 2).rounded() == x * 2)
        }
    }
}

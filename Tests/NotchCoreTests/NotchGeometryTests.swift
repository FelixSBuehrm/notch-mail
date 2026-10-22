import CoreGraphics
import Testing
@testable import NotchCore

@Suite("Notch geometry")
struct NotchGeometryTests {
    // A 1512x982 point screen with a notch between x=663 and x=849.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let left = CGRect(x: 0, y: 950, width: 663, height: 32)
    let right = CGRect(x: 849, y: 950, width: 663, height: 32)

    @Test func usesTheGapBetweenTheMenuBarAreasAsTheNotch() {
        let geometry = NotchGeometry.make(
            screenFrame: screen, safeAreaTop: 32,
            auxiliaryLeft: left, auxiliaryRight: right, menuBarHeight: 24
        )

        #expect(geometry.hasNotch)
        #expect(geometry.notchRect == CGRect(x: 663, y: 950, width: 186, height: 32))
    }

    @Test func fallsBackToMenuBarCentreWithoutNotch() {
        let geometry = NotchGeometry.make(
            screenFrame: screen, safeAreaTop: 0,
            auxiliaryLeft: nil, auxiliaryRight: nil, menuBarHeight: 24
        )

        #expect(!geometry.hasNotch)
        #expect(geometry.notchRect.midX == screen.midX)
        #expect(geometry.notchRect.maxY == screen.maxY)
        #expect(geometry.notchRect.height == 24)
        #expect(geometry.notchRect.width == NotchGeometry.fallbackWidth)
    }

    @Test func worksOnASecondScreenWithAnOffsetOrigin() {
        let external = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let geometry = NotchGeometry.make(
            screenFrame: external, safeAreaTop: 0,
            auxiliaryLeft: nil, auxiliaryRight: nil, menuBarHeight: 25
        )

        #expect(geometry.notchRect.midX == external.midX)
        #expect(geometry.notchRect.maxY == external.maxY)
    }

    @Test func panelHangsFromTheTopCentredOnTheNotch() {
        let geometry = NotchGeometry.make(
            screenFrame: screen, safeAreaTop: 32,
            auxiliaryLeft: left, auxiliaryRight: right, menuBarHeight: 24
        )
        let panel = geometry.panelFrame(size: CGSize(width: 500, height: 400))

        #expect(panel.midX == geometry.notchRect.midX)
        #expect(panel.maxY == screen.maxY)
        #expect(panel.size == CGSize(width: 500, height: 400))
    }

    @Test func hotRectCoversVisibleContentPlusSlack() {
        let geometry = NotchGeometry.make(
            screenFrame: screen, safeAreaTop: 32,
            auxiliaryLeft: left, auxiliaryRight: right, menuBarHeight: 24
        )
        let rect = geometry.hotRect(contentSize: CGSize(width: 200, height: 32), slack: 8)

        #expect(rect.width == 216)
        #expect(rect.minY == screen.maxY - 40)
        #expect(rect.maxY > screen.maxY)
        #expect(rect.midX == geometry.notchRect.midX)
    }

    @Test func pointerPinnedToTheTopEdgeCountsAsOnTheNotch() {
        let geometry = NotchGeometry.make(
            screenFrame: screen, safeAreaTop: 32,
            auxiliaryLeft: left, auxiliaryRight: right, menuBarHeight: 24
        )
        let rect = geometry.hotRect(contentSize: CGSize(width: 200, height: 32), slack: 0)

        // CGRect.contains excludes maxY; a pointer thrown upwards sits exactly there.
        #expect(rect.contains(CGPoint(x: geometry.notchRect.midX, y: screen.maxY)))
    }
}

import AppKit
import Testing

@testable import PresentSafe

@Suite("Notification cover geometry")
@MainActor
struct NotificationCoverGeometryTests {

    /// A 16:10 display with a 37pt menu bar and a 70pt Dock along the bottom.
    private let full = NSRect(x: 0, y: 0, width: 1728, height: 1117)
    private let visible = NSRect(x: 0, y: 70, width: 1728, height: 1010)

    @Test("Sits flush against the right edge")
    func flushRight() {
        let frame = NotificationZoneGuard.coverFrame(fullFrame: full, visibleFrame: visible)
        #expect(frame.maxX == full.maxX)
    }

    @Test("Reaches the bottom of the display, past the Dock")
    func flushBottom() {
        // Dock badges count unread messages, which is the same thing the cover
        // is hiding, so stopping at the visible frame would leave them showing.
        let frame = NotificationZoneGuard.coverFrame(fullFrame: full, visibleFrame: visible)
        #expect(frame.minY == full.minY)
        #expect(frame.minY < visible.minY)
    }

    @Test("Stops just under the menu bar rather than covering it")
    func stopsBelowMenuBar() {
        let frame = NotificationZoneGuard.coverFrame(fullFrame: full, visibleFrame: visible)
        #expect(frame.maxY == visible.maxY)
        #expect(frame.maxY < full.maxY)
    }

    @Test("Narrower than a banner's width is clamped to the screen")
    func clampsOnNarrowScreens() {
        let narrow = NSRect(x: 0, y: 0, width: 300, height: 600)
        let frame = NotificationZoneGuard.coverFrame(fullFrame: narrow, visibleFrame: narrow)
        #expect(frame.width == narrow.width)
        #expect(frame.minX == narrow.minX)
    }

    @Test("Works on a display placed above and left of the main one")
    func handlesNegativeOrigins() {
        // Secondary displays get negative origins in the global coordinate
        // space; anchoring to a hardcoded zero would put the cover off-screen.
        let secondary = NSRect(x: -2560, y: 900, width: 2560, height: 1440)
        let frame = NotificationZoneGuard.coverFrame(fullFrame: secondary, visibleFrame: secondary)
        #expect(frame.maxX == secondary.maxX)
        #expect(frame.minY == secondary.minY)
        #expect(secondary.contains(frame))
    }
}

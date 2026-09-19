import AppKit
import Testing

@testable import Drape

@Suite("Notification cover geometry")
@MainActor
struct NotificationCoverGeometryTests {

    /// A 16:10 display with a 37pt menu bar and a 70pt Dock along the bottom.
    private let full = NSRect(x: 0, y: 0, width: 1728, height: 1117)
    private let visible = NSRect(x: 0, y: 70, width: 1728, height: 1010)

    private var panel: NSRect {
        NotificationZoneGuard.coverFrame(fullFrame: full, visibleFrame: visible)
    }

    @Test("Floats inside the visible frame rather than touching the edges")
    func insetOnEveryVisibleEdge() {
        #expect(panel.maxX < visible.maxX)
        #expect(panel.maxY < visible.maxY)
        #expect(panel.minY > visible.minY)
    }

    @Test("The inset is the same on all three exposed sides")
    func insetIsUniform() {
        let right = visible.maxX - panel.maxX
        let top = visible.maxY - panel.maxY
        let bottom = panel.minY - visible.minY
        #expect(right == top)
        #expect(top == bottom)
    }

    @Test("Clears the menu bar and the Dock")
    func staysInsideTheUsableArea() {
        // visibleFrame already excludes both, so staying inside it is what
        // keeps the panel off the clock and off the Dock.
        #expect(visible.contains(panel))
        #expect(panel.maxY < full.maxY)
        #expect(panel.minY > full.minY)
    }

    @Test("Full height of the usable area, minus the insets")
    func spansTheUsableHeight() {
        // A banner stack grows downwards and its height is unknowable, so the
        // column runs the whole way rather than guessing at a card size.
        let inset = panel.minY - visible.minY
        #expect(panel.height == visible.height - inset * 2)
    }

    @Test("A screen narrower than a banner cannot push the panel off-screen")
    func clampsOnNarrowScreens() {
        let narrow = NSRect(x: 0, y: 0, width: 300, height: 600)
        let frame = NotificationZoneGuard.coverFrame(fullFrame: narrow, visibleFrame: narrow)
        #expect(narrow.contains(frame))
        #expect(frame.width > 0)
    }

    @Test("Works on a display placed above and left of the main one")
    func handlesNegativeOrigins() {
        // Secondary displays get negative origins in the global coordinate
        // space; anchoring to a hardcoded zero would put the panel off-screen.
        let secondary = NSRect(x: -2560, y: 900, width: 2560, height: 1440)
        let frame = NotificationZoneGuard.coverFrame(fullFrame: secondary, visibleFrame: secondary)
        #expect(secondary.contains(frame))
        #expect(frame.maxX < secondary.maxX)
    }
}

@Suite("Notification cover window")
@MainActor
struct NotificationCoverWindowTests {

    private let full = NSRect(x: 0, y: 0, width: 1728, height: 1117)
    private let visible = NSRect(x: 0, y: 70, width: 1728, height: 1010)

    @Test("The window is larger than the panel, so the shadow is not clipped")
    func windowLeavesRoomForTheShadow() {
        let panel = NotificationZoneGuard.coverFrame(fullFrame: full, visibleFrame: visible)
        let window = NotificationZoneGuard.windowFrame(fullFrame: full, visibleFrame: visible)

        #expect(window.contains(panel))
        #expect(window.width > panel.width)
        #expect(window.height > panel.height)
    }

    @Test("The window never leaves the display")
    func windowStaysOnScreen() {
        let window = NotificationZoneGuard.windowFrame(fullFrame: full, visibleFrame: visible)
        #expect(full.contains(window))
    }

    @Test("The insets place the panel exactly where it belongs")
    func insetsMatchTheGaps() {
        let panel = NotificationZoneGuard.coverFrame(fullFrame: full, visibleFrame: visible)
        let window = NotificationZoneGuard.windowFrame(fullFrame: full, visibleFrame: visible)
        let insets = NotificationZoneGuard.contentInsets(fullFrame: full, visibleFrame: visible)

        #expect(insets.leading == panel.minX - window.minX)
        #expect(insets.trailing == window.maxX - panel.maxX)
        #expect(insets.top == window.maxY - panel.maxY)
        #expect(insets.bottom == panel.minY - window.minY)

        #expect(window.width - insets.leading - insets.trailing == panel.width)
        #expect(window.height - insets.top - insets.bottom == panel.height)
    }

    @Test("A screen too small for the margin still stays on screen")
    func narrowScreenCannotOverflow() {
        let narrow = NSRect(x: 0, y: 0, width: 320, height: 600)
        let window = NotificationZoneGuard.windowFrame(fullFrame: narrow, visibleFrame: narrow)
        #expect(narrow.contains(window))
    }
}

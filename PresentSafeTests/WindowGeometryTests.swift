import AppKit
import Testing

@testable import PresentSafe

@Suite("Window geometry")
struct WindowGeometryTests {

    /// A 1117pt-tall primary display.
    private let primaryHeight: CGFloat = 1117

    @Test("Flips the origin from top-left to bottom-left")
    func flipsVertically() {
        // A window 100pt down from the top of a 1117pt display, 600pt tall,
        // has its AppKit bottom edge at 1117 - 700 = 417.
        let cg = CGRect(x: 200, y: 100, width: 800, height: 600)
        let ns = WindowGeometry.appKitRect(fromCoreGraphics: cg, primaryHeight: primaryHeight)

        #expect(ns.minX == 200)
        #expect(ns.minY == 417)
        #expect(ns.width == 800)
        #expect(ns.height == 600)
    }

    @Test("A window at the very top lands at the very top")
    func topEdgeStaysAtTheTop() {
        let cg = CGRect(x: 0, y: 0, width: 400, height: 300)
        let ns = WindowGeometry.appKitRect(fromCoreGraphics: cg, primaryHeight: primaryHeight)
        #expect(ns.maxY == primaryHeight)
    }

    @Test("A window at the very bottom lands at the very bottom")
    func bottomEdgeStaysAtTheBottom() {
        let cg = CGRect(x: 0, y: primaryHeight - 300, width: 400, height: 300)
        let ns = WindowGeometry.appKitRect(fromCoreGraphics: cg, primaryHeight: primaryHeight)
        #expect(ns.minY == 0)
    }

    @Test("Converting twice returns the original")
    func conversionIsItsOwnInverse() {
        // The flip is symmetric, which is the cheapest guard against someone
        // "fixing" it with an off-by-one later.
        let cg = CGRect(x: 120, y: 340, width: 500, height: 420)
        let ns = WindowGeometry.appKitRect(fromCoreGraphics: cg, primaryHeight: primaryHeight)
        let back = WindowGeometry.appKitRect(
            fromCoreGraphics: CGRect(x: ns.minX, y: ns.minY, width: ns.width, height: ns.height),
            primaryHeight: primaryHeight
        )
        #expect(back == cg)
    }

    @Test("A display above the primary one gets negative CoreGraphics y")
    func handlesDisplaysAboveThePrimary() {
        // Secondary displays placed above the primary report negative y in
        // CoreGraphics. The result must sit above the primary's top edge.
        let cg = CGRect(x: 0, y: -900, width: 1000, height: 700)
        let ns = WindowGeometry.appKitRect(fromCoreGraphics: cg, primaryHeight: primaryHeight)
        #expect(ns.minY > primaryHeight)
    }
}

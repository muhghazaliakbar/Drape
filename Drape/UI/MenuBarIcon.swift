import AppKit

/// The mark in the menu bar: the same screen and curtain as the app icon,
/// reduced to what survives at 18pt.
///
/// It was an SF Symbol at first, which left the app wearing two different marks
/// — an eye in the menu bar, a curtained screen in the Dock. Drawing it here
/// costs little and the curtain turns out to carry the state better anyway:
/// rolled up when idle, drawn down when protecting. That is the app's whole
/// job, stated in one shape.
///
/// Template images, so macOS inverts them for a light or dark menu bar and for
/// the highlight when the menu is open. A coloured image would be wrong in all
/// three cases — which is why the app icon cannot simply be reused here.
///
/// Main actor because the two cached images are `NSImage`, which is not
/// `Sendable`. Swift 6.0 rejects that outright in a static property; Swift 6.4
/// says nothing at all, so this compiled locally and broke CI — the reason the
/// workflow builds on an older Xcode than anyone here develops on.
@MainActor
enum MenuBarIcon {
    private static let side: CGFloat = 18

    static let idle = make(covered: false)
    static let covering = make(covered: true)

    static func image(covering: Bool) -> NSImage {
        covering ? Self.covering : idle
    }

    private static func make(covered: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(covered: covered, in: ctx)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = covered
            ? String(localized: "Present Mode on")
            : String(localized: "Present Mode off")
        return image
    }

    /// Pure CoreGraphics on purpose: AppKit may call a drawing handler off the
    /// main thread, and nothing here may repeat the Text Input Sources mistake
    /// of touching an API that insists on the main one.
    private static func draw(covered: Bool, in ctx: CGContext) {
        ctx.setShouldAntialias(true)

        let screen = CGRect(x: 1.4, y: 3.2, width: 15.2, height: 11.6)
        let outline = CGPath(roundedRect: screen, cornerWidth: 2.6, cornerHeight: 2.6, transform: nil)

        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))

        ctx.saveGState()
        ctx.addPath(outline)
        ctx.clip()
        if covered {
            // Drawn down over the top of the screen.
            let hem = screen.minY + screen.height * 0.44
            ctx.fill(CGRect(x: screen.minX, y: hem, width: screen.width, height: screen.height))
        } else {
            // Rolled up and tucked under the top edge.
            ctx.fill(CGRect(x: screen.minX, y: screen.maxY - 3, width: screen.width, height: 3))
        }
        ctx.restoreGState()

        ctx.addPath(outline)
        ctx.setLineWidth(1.5)
        ctx.strokePath()

        // Two strokes of stand, just enough to read as a display rather than a
        // plain rounded rectangle.
        ctx.setLineWidth(1.4)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 9, y: 3.2))
        ctx.addLine(to: CGPoint(x: 9, y: 1.6))
        ctx.move(to: CGPoint(x: 6.2, y: 1.5))
        ctx.addLine(to: CGPoint(x: 11.8, y: 1.5))
        ctx.strokePath()
    }
}

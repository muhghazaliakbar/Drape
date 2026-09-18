import AppKit
import SwiftUI

/// Hides notification banners while Present Mode is on.
///
/// macOS offers no supported way to suppress another app's banners, so
/// PresentSafe covers them instead: a panel of its own, parked over the corner
/// they occupy. Because the panel is part of the screen, whatever is capturing
/// that screen captures the panel too — which is the point.
///
/// The first version left that panel up for the whole session. It worked, and
/// it was miserable: a dead slab over a chunk of your display for the length of
/// a presentation, on the chance that something might arrive. This version
/// watches for banners and covers only while one is actually up.
///
/// Best-effort by nature, and worth stating plainly:
/// - The banner rectangle is not published. macOS exposes a full-screen host
///   window for Notification Center, not the banner's own frame, so the covered
///   region is a well-placed estimate rather than a measurement.
/// - Someone sharing a single *window* rather than a whole screen never sees
///   the cover, since it is a window of its own.
@MainActor
final class NotificationZoneGuard: PresentGuard {
    let id = "notificationZone"
    let title = String(localized: "Cover the notification corner")
    let summary = String(localized: "Hides banners as they appear, on every display.")
    let symbolName = "bell.slash"
    let isEnabledByDefault = true

    /// Banners are about 344pt wide; the cover is a little wider to allow for
    /// shadows and the odd oversized banner.
    private static let coverWidth: CGFloat = 372
    private static let edgeInset: CGFloat = 10

    /// Slack around the panel for its shadow to fall into.
    ///
    /// The window used to be exactly the panel's size, so the shadow was cut
    /// off square by the window edge — which is what put a hard right angle
    /// outside each rounded corner.
    private static let shadowMargin: CGFloat = 44
    private static let pollInterval = Duration.milliseconds(250)

    /// Drives the cover's fade from inside SwiftUI. Animating
    /// `NSWindow.alphaValue` instead pushes a large surface through the window
    /// server and visibly steps — the same lesson the confirmation HUD taught.
    @MainActor
    final class Phase: ObservableObject {
        @Published var isVisible = false
    }

    /// Fast in, unhurried out. The asymmetry is the whole point: every frame of
    /// a slow fade-in is a frame where the banner is legible through a
    /// half-transparent cover, which is precisely what this guard exists to
    /// prevent. Going away is not urgent, so it can take its time.
    private static let appear = Animation.easeOut(duration: 0.18)
    private static let disappear = Animation.easeInOut(duration: 0.45)
    private static let disappearDuration = Duration.milliseconds(460)

    private var covers: [NSWindow] = []
    private var screenObserver: (any NSObjectProtocol)?
    private var watchTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var isCovering = false
    private let phase = Phase()

    func activate() async throws {
        rebuildCovers()
        startWatchingForBanners()

        // The whole point of this app is the moment you connect to a projector,
        // and that moment fires this notification. Without it, a display added
        // after Present Mode is switched on stays completely uncovered — the one
        // screen everybody is actually looking at.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.rebuildCovers()
            }
        }
    }

    func deactivate() async {
        watchTask?.cancel()
        watchTask = nil
        hideTask?.cancel()
        hideTask = nil

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        removeCovers()
    }

    // MARK: - Detection

    /// True while macOS has a Notification Center window on screen.
    ///
    /// Verified rather than assumed: the window is absent with no banner up and
    /// appears for exactly as long as one is displayed. Owner names and bounds
    /// come back from `CGWindowListCopyWindowInfo` without Screen Recording
    /// permission — only window *titles* are withheld — which keeps this guard
    /// inside the app's no-permissions rule.
    nonisolated private static func bannerIsOnScreen() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        return windows.contains { window in
            (window[kCGWindowOwnerName as String] as? String) == "Notification Center"
        }
    }

    private func startWatchingForBanners() {
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                // Measured at 0.5ms a call. Cheap, but this app runs during
                // presentations, so it stays off the main thread regardless.
                let showing = await Task.detached(priority: .utility) {
                    NotificationZoneGuard.bannerIsOnScreen()
                }.value

                guard !Task.isCancelled, let self else { return }
                self.setCovering(showing)

                try? await Task.sleep(for: NotificationZoneGuard.pollInterval)
            }
        }
    }

    private func setCovering(_ covering: Bool) {
        guard covering != isCovering else { return }
        isCovering = covering
        hideTask?.cancel()

        if covering {
            for cover in covers {
                cover.alphaValue = 1
                cover.orderFrontRegardless()
            }
            withAnimation(Self.appear) { phase.isVisible = true }
        } else {
            withAnimation(Self.disappear) { phase.isVisible = false }
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: Self.disappearDuration)
                guard !Task.isCancelled, let self, !self.isCovering else { return }
                for cover in self.covers { cover.orderOut(nil) }
            }
        }
    }

    // MARK: - Covers

    private func rebuildCovers() {
        removeCovers()
        covers = NSScreen.screens.map { screen in
            makeCover(
                frame: Self.windowFrame(fullFrame: screen.frame, visibleFrame: screen.visibleFrame),
                insets: Self.contentInsets(fullFrame: screen.frame, visibleFrame: screen.visibleFrame)
            )
        }
        if isCovering {
            for cover in covers { cover.orderFrontRegardless() }
        }
    }

    private func removeCovers() {
        for cover in covers { cover.orderOut(nil) }
        covers = []
        isCovering = false
        phase.isVisible = false
    }

    /// A full-height column down the right-hand side, inset from the visible
    /// frame so it clears the menu bar and the Dock.
    ///
    /// Full height rather than a banner-sized card, because a stack grows
    /// downwards and there is no way to learn how tall it got: macOS publishes
    /// only a full-screen host window for Notification Center, never the
    /// banners' own frames. A fixed height would be a guess that leaks the
    /// moment three notifications arrive at once.
    static func coverFrame(on screen: NSScreen) -> NSRect {
        coverFrame(fullFrame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    /// Split out from `NSScreen` so the geometry can be tested. Where the panel
    /// sits is a claim about numbers, and `NSScreen` cannot be constructed.
    static func coverFrame(fullFrame full: NSRect, visibleFrame visible: NSRect) -> NSRect {
        let width = min(coverWidth, max(0, visible.width - edgeInset * 2))
        return NSRect(
            x: visible.maxX - width - edgeInset,
            y: visible.minY + edgeInset,
            width: width,
            height: max(0, visible.height - edgeInset * 2)
        )
    }

    /// The window that hosts the panel: the panel plus room on every side for
    /// its shadow, clipped to the display. Everything outside the panel is
    /// transparent and passes clicks through.
    static func windowFrame(fullFrame full: NSRect, visibleFrame visible: NSRect) -> NSRect {
        coverFrame(fullFrame: full, visibleFrame: visible)
            .insetBy(dx: -shadowMargin, dy: -shadowMargin)
            .intersection(full)
    }

    /// How far the panel sits inside its window on each side, so the content
    /// can be padded back into place.
    static func contentInsets(fullFrame full: NSRect, visibleFrame visible: NSRect) -> EdgeInsets {
        let panel = coverFrame(fullFrame: full, visibleFrame: visible)
        let window = windowFrame(fullFrame: full, visibleFrame: visible)
        return EdgeInsets(
            top: window.maxY - panel.maxY,
            leading: panel.minX - window.minX,
            bottom: panel.minY - window.minY,
            trailing: window.maxX - panel.maxX
        )
    }

    private func makeCover(frame: NSRect, insets: EdgeInsets) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(
            rootView: NotificationCoverView(phase: phase, insets: insets)
        )
        // Clear and non-opaque so the panel's own rounded corners survive.
        window.backgroundColor = .clear
        window.isOpaque = false
        // The window must not draw a shadow of its own. Around a non-opaque
        // window hosting a `.behindWindow` effect view, macOS traces one along
        // the effect view's bounds — which showed up as a dark outline and a
        // pale halo sitting outside the panel, on top of the shadow SwiftUI
        // already draws.
        window.hasShadow = false
        window.alphaValue = 0
        // Purely visual: clicks pass straight through, so the cover can never
        // strand the user behind a rectangle they cannot dismiss.
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.setFrame(frame, display: false)
        return window
    }
}

/// What the audience sees instead of the notification.
///
/// Glass rather than a solid slab: it reads as a deliberate surface laid over
/// the screen instead of a rectangle that failed to render.
///
/// The tint over the glass is the one concession to what this panel is for.
/// Blur alone reduces text to illegibility but still passes shapes and colour,
/// so a viewer could tell which app had just messaged you. `tintOpacity` is the
/// dial: lower it for more glass, raise it for more cover.
private struct NotificationCoverView: View {
    private static let cornerRadius: CGFloat = 14
    private static let tintOpacity: Double = 0.18
    private static let material: NSVisualEffectView.Material = .hudWindow

    @ObservedObject var phase: NotificationZoneGuard.Phase
    let insets: EdgeInsets

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    var body: some View {
        panel
            // The window is larger than the panel so the shadow has somewhere
            // to fall. Without the slack it was clipped square by the window
            // edge, which drew a hard right angle outside each rounded corner.
            .padding(insets)
            .opacity(phase.isVisible ? 1 : 0)
            .ignoresSafeArea()
    }

    private var panel: some View {
        BackdropView(material: Self.material, cornerRadius: Self.cornerRadius)
            .clipShape(shape)
            .overlay { tint }
            .overlay { rim }
            .overlay(alignment: .top) { label }
            .shadow(color: .black.opacity(0.28), radius: 16, y: 2)
    }

    private var tint: some View {
        shape.fill(Color.black.opacity(Self.tintOpacity))
    }

    /// A specular edge along the lit side, which is what stops a translucent
    /// panel from looking like a smudge.
    private var rim: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [.white.opacity(0.28), .white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottom
            ),
            lineWidth: 1
        )
    }

    private var label: some View {
        HStack(spacing: 7) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 13))
            Text("Notification hidden")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.top, 24)
    }
}

/// A translucent backdrop that samples the screen behind the window.
///
/// SwiftUI's `.regularMaterial` blends against whatever is inside the same
/// window. In a borderless overlay there is nothing inside it, so the material
/// resolves to a flat colour and the panel comes out looking opaque. Only
/// `NSVisualEffectView` with `.behindWindow` blending reaches past the window
/// to the screen underneath, which is the whole effect.
private struct BackdropView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = .behindWindow
        // Without `.active` the blur stops whenever the app is not frontmost —
        // which, for a menu bar utility, is always.
        view.state = .active

        // Rounded on the layer as well as by SwiftUI's `clipShape`. The clip
        // shapes what SwiftUI composites — including the shadow — while this
        // shapes the AppKit view itself, which is what the window server reads
        // when it decides where the surface ends.
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

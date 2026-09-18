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
        covers = NSScreen.screens.map { makeCover(over: Self.coverFrame(on: $0)) }
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

    /// The full right-hand column of a screen, flush to the right and bottom
    /// edges and stopping just under the menu bar.
    ///
    /// Full height rather than a banner-sized card, because a stack grows
    /// downwards and there is no way to learn how tall it got: macOS publishes
    /// only a full-screen host window for Notification Center, never the
    /// banners' own frames. A fixed height would be a guess that leaks the
    /// moment three notifications arrive at once.
    ///
    /// It reaches past the Dock deliberately — Dock badges count unread
    /// messages, which is the same thing this guard is covering up.
    static func coverFrame(on screen: NSScreen) -> NSRect {
        coverFrame(fullFrame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    /// Split out from `NSScreen` so the geometry can be tested. "Flush to the
    /// edges" is a claim about numbers, and `NSScreen` cannot be constructed.
    static func coverFrame(fullFrame full: NSRect, visibleFrame visible: NSRect) -> NSRect {
        let width = min(coverWidth, full.width)
        return NSRect(
            x: full.maxX - width,
            y: full.minY,
            width: width,
            height: visible.maxY - full.minY
        )
    }

    private func makeCover(over frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: NotificationCoverView(phase: phase))
        // Clear and non-opaque so the panel's own rounded corners survive; the
        // panel itself is fully opaque, because a blurred material would leave
        // a banner's shape and colour readable through it.
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
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
/// the screen instead of a rectangle that failed to render. Only the leading
/// corners are rounded, because the panel is flush with the right, top and
/// bottom edges — a shape that hugs the display rather than floating on it.
///
/// The tint over the glass is the one concession to what this panel is for.
/// Pure material blurs text into illegibility but still passes shapes and
/// colour, so a viewer could tell which app had just messaged you. `tintOpacity`
/// is the dial: lower it for more glass, raise it for more cover.
private struct NotificationCoverView: View {
    private static let cornerRadius: CGFloat = 26
    private static let tintOpacity: Double = 0.28

    @ObservedObject var phase: NotificationZoneGuard.Phase

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: Self.cornerRadius,
                bottomLeading: Self.cornerRadius,
                bottomTrailing: 0,
                topTrailing: 0
            ),
            style: .continuous
        )
    }

    var body: some View {
        glass
            .overlay { tint }
            .overlay { rim }
            .overlay(alignment: .top) { label }
            .shadow(color: .black.opacity(0.25), radius: 18, x: -8)
            .opacity(phase.isVisible ? 1 : 0)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }

    private var tint: some View {
        shape.fill(Color(nsColor: .windowBackgroundColor).opacity(Self.tintOpacity))
    }

    /// A specular edge along the lit side, which is what stops a translucent
    /// panel from looking like a smudge.
    private var rim: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [.white.opacity(0.30), .white.opacity(0.05)],
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

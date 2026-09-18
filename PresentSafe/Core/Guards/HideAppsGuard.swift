import AppKit
import OSLog
import SwiftUI

/// Hides the apps the user marked as sensitive — password managers, chat
/// clients, mail, whatever leaks when a screen goes up on a projector.
///
/// This uses `NSRunningApplication.hide()`, which is the programmatic equivalent
/// of pressing Cmd-H. That choice is deliberate: it needs no Accessibility
/// permission, so a fresh install protects you on the very first run instead of
/// sending you to System Settings before it does anything useful.
@MainActor
final class HideAppsGuard: PresentGuard {
    let id = "hideApps"
    let title = String(localized: "Hide sensitive apps")
    let summary = String(localized: "Hides the apps you choose, and brings them back afterwards.")
    let symbolName = "eye.slash"
    let isEnabledByDefault = true

    private let preferences: Preferences

    /// Only the apps this guard actually hid. Apps the user had already hidden
    /// are left alone on the way out, so Present Mode never un-hides something
    /// the user deliberately put away.
    private var hiddenByUs: [NSRunningApplication] = []
    private var launchObserver: (any NSObjectProtocol)?
    private var activationObserver: (any NSObjectProtocol)?
    private var unhideObserver: (any NSObjectProtocol)?
    private var sweepTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "dev.justghali.PresentSafe", category: "HideApps")

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func activate() async throws {
        let targets = preferences.sensitiveBundleIDs
        guard !targets.isEmpty else {
            throw GuardError.notConfigured(String(localized: "Pick at least one app in Settings."))
        }

        hiddenByUs = NSWorkspace.shared.runningApplications.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return targets.contains(bundleID) && !app.isHidden
        }

        for app in hiddenByUs {
            app.hide()
        }

        // A sensitive app launched mid-presentation — Slack reopening, Mail
        // raised by a clicked link — arrives frontmost and unhidden, which is
        // the worst possible moment for it.
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            // Neither `Notification` nor `NSRunningApplication` is Sendable, so
            // nothing from the notification can cross into the isolated closure.
            // The pid can: it is an Int32, and re-resolving it on the main actor
            // gives back an equivalent object.
            let pid = Self.processIdentifier(from: notification)

            MainActor.assumeIsolated { [weak self] in
                guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { return }
                self?.refuseLaunch(of: app)
            }
        }

        // Hiding once is not the same as staying hidden. Without this, a stray
        // Cmd-Tab mid-presentation puts the user's DMs back on the shared
        // screen — which is the likeliest way this app fails in practice, and
        // it fails silently.
        //
        // Two notifications, because one is not enough. Measured, not assumed:
        // `didActivate` fires for an app returning from hidden while its
        // `isHidden` is still `true` — macOS has not applied the unhide yet —
        // so acting on that alone hides nothing. `didUnhide` arrives afterwards
        // with the app genuinely visible, and that is the one that matters.
        // `didActivate` still earns its place for an app that was merely in the
        // background and never hidden at all, where no unhide ever happens.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let pid = Self.processIdentifier(from: notification)

            MainActor.assumeIsolated { [weak self] in
                guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { return }
                self?.handleActivation(of: app)
            }
        }

        startSweeping()

        unhideObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let pid = Self.processIdentifier(from: notification)

            MainActor.assumeIsolated { [weak self] in
                guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { return }
                guard self?.isSensitive(app) == true else { return }
                self?.block(app, trigger: "unhide")
            }
        }
    }

    /// A slow backstop for everything the notifications miss.
    ///
    /// Chiefly a snooze running out while the user is still in the app: no
    /// activation follows, because they never left. It also catches any
    /// notification that never arrives, which for a privacy tool is worth one
    /// cheap check a second.
    private func startSweeping() {
        sweepTask?.cancel()
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }

                guard let frontmost = NSWorkspace.shared.frontmostApplication,
                      frontmost.bundleIdentifier != Bundle.main.bundleIdentifier,
                      self.isSensitive(frontmost),
                      !frontmost.isHidden,
                      BlockedAppOverlay.shared.blockedApp != frontmost
                else { continue }

                self.block(frontmost, trigger: "sweep")
            }
        }
    }

    nonisolated private static func processIdentifier(from notification: Notification) -> pid_t? {
        (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
            .processIdentifier
    }

    func deactivate() async {
        for observer in [launchObserver, activationObserver, unhideObserver].compactMap(\.self) {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        launchObserver = nil
        activationObserver = nil
        unhideObserver = nil
        sweepTask?.cancel()
        sweepTask = nil
        BlockedAppOverlay.shared.dismiss()
        // Snoozes last one session. Turning protection off and on again is a
        // deliberate act and should mean what it says.
        SnoozeRegistry.shared.clear()

        for app in hiddenByUs where !app.isTerminated {
            app.unhide()
        }
        hiddenByUs = []
    }

    /// Puts a sensitive app back after the user brought it forward.
    ///
    /// An app that simply bounces reads as a bug, so this always explains
    /// itself. The user is not locked out: the shortcut is one press away, and
    /// the card says so.
    private func handleActivation(of app: NSRunningApplication) {
        // Our own overlay takes key status to make its button usable, which
        // activates this app. Reacting to that would dismiss the overlay the
        // instant it appeared.
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }

        // An app still marked hidden is mid-unhide; `didUnhide` follows and
        // handles it. Acting on both would cover it twice.
        if isSensitive(app), !app.isHidden {
            block(app, trigger: "activate")
            return
        }

        // The user moved on. Now, and only now, the blocked app is put away —
        // which is what the overlay told them would happen.
        if let blocked = BlockedAppOverlay.shared.blockedApp, blocked != app {
            putAway(blocked)
        }
    }

    private func isSensitive(_ app: NSRunningApplication) -> Bool {
        guard preferences.keepsSensitiveAppsHidden,
              let bundleID = app.bundleIdentifier,
              preferences.sensitiveBundleIDs.contains(bundleID)
        else { return false }
        // A snoozed app is simply not sensitive for the moment, which makes one
        // check cover blocking, covering and putting away all at once.
        return !SnoozeRegistry.shared.isSnoozed(bundleID)
    }

    /// Covers the app rather than hiding it immediately.
    ///
    /// Hiding on sight worked and felt broken: an app that bounces with no
    /// explanation reads as a crash, and the abrupt change of frontmost app is
    /// disorienting mid-presentation. The cover holds everything still and says
    /// what happened.
    private func block(_ app: NSRunningApplication, trigger: String) {
        let name = app.localizedName ?? app.bundleIdentifier ?? "App"

        // An app with windows on screen gets them covered, each at its own
        // size. One that has none — just launched, or every window closed —
        // has nothing to cover, so the card carries the message alone.
        let covered = BlockedAppOverlay.shared.cover(app)
        logger.notice("Blocking \(app.bundleIdentifier ?? "?", privacy: .public) on \(trigger, privacy: .public); covered windows: \(covered)")

        PresentModeHUD.shared.show(.blocked(appName: name, bundleID: app.bundleIdentifier))
    }

    private func putAway(_ app: NSRunningApplication) {
        BlockedAppOverlay.shared.dismiss()
        guard !app.isTerminated else { return }

        // The result of `hide()` is deliberately not used as a condition. It
        // reports `false` in situations where the hide still lands, so gating
        // on it silently skips the very case this exists for.
        let reported = app.hide()
        logger.notice("Put away \(app.bundleIdentifier ?? "?", privacy: .public); hide() reported \(reported)")

        if !hiddenByUs.contains(app) {
            hiddenByUs.append(app)
        }
    }

    var configuration: AnyView? {
        AnyView(HideAppsConfiguration(preferences: preferences))
    }

    /// Closes a sensitive app that was launched while Present Mode is on.
    ///
    /// Covering is the right answer for an app the user already had open —
    /// it keeps their work and their window where they left them. A launch is
    /// different: there is nothing to preserve, and the user asked for the app
    /// not to open at all. So this closes it and offers Snooze, which is the
    /// only way through.
    ///
    /// Deliberately limited to launches. Closing an app that has been running
    /// for hours could throw away unsaved work, which is not a trade this tool
    /// gets to make on the user's behalf. `terminate()` is also the polite
    /// variant — the app is asked to quit and can still save — rather than
    /// `forceTerminate()`.
    private func refuseLaunch(of app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        guard isSensitive(app) else {
            // Recorded, because "nothing happened" is the hardest failure to
            // diagnose from the outside.
            logger.debug("Ignoring launch of \(bundleID, privacy: .public): not sensitive or snoozed")
            return
        }

        // Hide first, quit second. Measured: terminate() alone takes over a
        // second to land, which is ample time for the window to appear and be
        // read by everyone watching. Hiding suppresses the window while the
        // quit request works its way through.
        app.hide()
        let reported = app.terminate()
        logger.notice("Refusing launch of \(bundleID, privacy: .public); terminate() reported \(reported)")

        PresentModeHUD.shared.show(.blocked(appName: app.localizedName ?? bundleID, bundleID: bundleID))
        keepDown(app, bundleID: bundleID)
    }

    /// Keeps asking until the app is hidden or gone.
    ///
    /// `hide()` reports failure while an app is still launching and then takes
    /// effect a moment later — measured at around 600ms — so a single call is a
    /// coin toss. An app that draws its window faster than that would otherwise
    /// be on screen for the whole time the quit request is in flight.
    private func keepDown(_ app: NSRunningApplication, bundleID: String) {
        Task { [weak self] in
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !app.isTerminated else { return }
                // Snoozing mid-flight means the user asked for it after all.
                guard self.isSensitive(app) else { return }
                if !app.isHidden { app.hide() }
            }

            guard let self, !app.isTerminated, self.isSensitive(app) else { return }
            let retried = app.terminate()
            self.logger.notice("Retried refusing \(bundleID, privacy: .public); terminate() reported \(retried)")
        }
    }

}

private struct HideAppsConfiguration: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Toggle(isOn: $preferences.keepsSensitiveAppsHidden) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep them hidden")
                Text("Puts an app back if you open it while Present Mode is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }
}

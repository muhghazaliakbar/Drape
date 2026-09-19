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
    private var willLaunchObserver: (any NSObjectProtocol)?
    private var activationObserver: (any NSObjectProtocol)?
    private var unhideObserver: (any NSObjectProtocol)?
    private var sweepTask: Task<Void, Never>?

    /// The last app the user was actually working in. Refusing a launch means
    /// giving this focus straight back, which is the difference between "the
    /// app never opened" and "something flashed past and stole my keyboard".
    private var lastSafeFrontmost: NSRunningApplication?

    /// Launches already being refused. `willLaunch` and `didLaunch` both fire
    /// for the same launch, and starting twice would leave two loops fighting
    /// over one process.
    private var refusing: Set<pid_t> = []

    /// One frame at 60Hz. Anything slower and the app holds the menu bar long
    /// enough to see.
    private static let tightTick = Duration.milliseconds(16)
    private static let relaxedTick = Duration.milliseconds(100)
    private static let tightWindow = Duration.milliseconds(800)
    /// How long an app gets to honour a polite quit before it is killed.
    private static let politeQuitGrace = Duration.milliseconds(500)
    private let logger = Logger(subsystem: "dev.justghali.Drape", category: "HideApps")

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

        // Seed it now, or a launch refused before the user has switched apps
        // has nothing to hand focus back to.
        if let frontmost = NSWorkspace.shared.frontmostApplication, !isSensitive(frontmost) {
            lastSafeFrontmost = frontmost
        }

        // A sensitive app launched mid-presentation — Slack reopening, Mail
        // raised by a clicked link — arrives frontmost and unhidden, which is
        // the worst possible moment for it.
        // Both notifications. `willLaunch` arrives about 180ms earlier —
        // measured — and that head start is most of the difference between "it
        // flickered" and "nothing happened". `didLaunch` stays as the backstop
        // for launches that never announce themselves early.
        willLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let pid = Self.processIdentifier(from: notification)
            MainActor.assumeIsolated { [weak self] in
                guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { return }
                self?.refuseLaunch(of: app)
            }
        }

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

    /// Returns the user to whatever they were doing.
    private func restoreFocus() {
        guard let previous = lastSafeFrontmost, !previous.isTerminated else { return }
        previous.activate()
    }

    nonisolated private static func processIdentifier(from notification: Notification) -> pid_t? {
        (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
            .processIdentifier
    }

    func deactivate() async {
        for observer in [launchObserver, willLaunchObserver, activationObserver, unhideObserver].compactMap(\.self) {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        launchObserver = nil
        willLaunchObserver = nil
        activationObserver = nil
        refusing.removeAll()
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
        if !isSensitive(app) {
            lastSafeFrontmost = app
        }

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

        guard refusing.insert(app.processIdentifier).inserted else { return }

        logger.notice("Refusing launch of \(bundleID, privacy: .public)")
        PresentModeHUD.shared.show(.blocked(appName: app.localizedName ?? bundleID, bundleID: bundleID))
        suppress(app, bundleID: bundleID)
    }

    /// Holds a refused launch down until the process is gone.
    ///
    /// All of this is timing, measured on real launches: `hide()` reports
    /// failure while the app is still starting and only lands some hundreds of
    /// milliseconds later; the app grabs focus for itself once it finishes
    /// launching, which is *after* the first attempt to hand focus back; and
    /// its window arrives around 1.2s in.
    ///
    /// So the loop runs at frame rate for the first stretch instead of politely
    /// every tenth of a second. At 100ms the app can hold the menu bar for six
    /// frames — which is precisely the flicker this exists to remove.
    private func suppress(_ app: NSRunningApplication, bundleID: String) {
        Task { [weak self] in
            let start = ContinuousClock.now
            var askedToQuit = false

            while !app.isTerminated {
                guard let self else { return }
                // Snoozing mid-flight means the user asked for it after all.
                guard self.isSensitive(app) else { break }

                if !app.isHidden { app.hide() }
                if NSWorkspace.shared.frontmostApplication == app { self.restoreFocus() }

                // A quit request before the app is ready is simply refused, so
                // it waits until there is something there to ask.
                if !askedToQuit, app.isFinishedLaunching {
                    askedToQuit = app.terminate()
                }

                let elapsed = start.duration(to: .now)
                if elapsed > Self.politeQuitGrace {
                    // Asked nicely for long enough. Measured, this lands in
                    // under 100ms where the polite request takes over a second.
                    let forced = app.forceTerminate()
                    self.logger.notice("Forced \(bundleID, privacy: .public); reported \(forced)")
                    break
                }

                try? await Task.sleep(for: elapsed < Self.tightWindow ? Self.tightTick : Self.relaxedTick)
            }

            self?.refusing.remove(app.processIdentifier)
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

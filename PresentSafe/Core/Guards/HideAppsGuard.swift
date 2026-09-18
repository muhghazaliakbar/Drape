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

        // Hiding once at activation is not enough. A sensitive app launched
        // mid-presentation — Slack reopening, Mail relaunched by a link — arrives
        // frontmost and unhidden, which is the worst possible moment for it.
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
                self?.hideIfSensitive(app)
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
                // An app still marked hidden is mid-unhide; `didUnhide` will
                // follow and handle it. Acting twice would double the card.
                guard !app.isHidden else { return }
                self?.putBackIfSensitive(app, trigger: "activate")
            }
        }

        unhideObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let pid = Self.processIdentifier(from: notification)

            MainActor.assumeIsolated { [weak self] in
                guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { return }
                self?.putBackIfSensitive(app, trigger: "unhide")
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
    private func putBackIfSensitive(_ app: NSRunningApplication, trigger: String) {
        guard preferences.keepsSensitiveAppsHidden,
              let bundleID = app.bundleIdentifier,
              preferences.sensitiveBundleIDs.contains(bundleID)
        else { return }

        // The result of `hide()` is deliberately not used as a condition. It
        // reports `false` in situations where the hide still lands, so gating
        // on it silently skips the very case this exists for.
        let reported = app.hide()
        logger.info("Put back \(bundleID, privacy: .public) on \(trigger, privacy: .public); hide() reported \(reported)")

        if !hiddenByUs.contains(app) {
            hiddenByUs.append(app)
        }
        PresentModeHUD.shared.show(.blocked(appName: app.localizedName ?? bundleID))
    }

    var configuration: AnyView? {
        AnyView(HideAppsConfiguration(preferences: preferences))
    }

    private func hideIfSensitive(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
              // Read preferences now rather than reusing the set captured at
              // activation, so changes made in Settings take effect immediately.
              preferences.sensitiveBundleIDs.contains(bundleID),
              !hiddenByUs.contains(app)
        else { return }

        // An app that has only just launched may refuse to hide while it is
        // still bringing up its first window, so retry once.
        if app.hide() {
            hiddenByUs.append(app)
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !app.isTerminated, app.hide() else { return }
                hiddenByUs.append(app)
            }
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

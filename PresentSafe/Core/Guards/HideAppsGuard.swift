import AppKit

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
    let title = "Hide sensitive apps"
    let summary = "Hides the apps you choose, and brings them back afterwards."
    let symbolName = "eye.slash"
    let isEnabledByDefault = true

    private let preferences: Preferences

    /// Only the apps this guard actually hid. Apps the user had already hidden
    /// are left alone on the way out, so Present Mode never un-hides something
    /// the user deliberately put away.
    private var hiddenByUs: [NSRunningApplication] = []
    private var launchObserver: (any NSObjectProtocol)?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func activate() async throws {
        let targets = preferences.sensitiveBundleIDs
        guard !targets.isEmpty else {
            throw GuardError.notConfigured("pick at least one app in Settings")
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
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .processIdentifier

            MainActor.assumeIsolated { [weak self] in
                guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { return }
                self?.hideIfSensitive(app)
            }
        }
    }

    func deactivate() async {
        if let launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
            self.launchObserver = nil
        }

        for app in hiddenByUs where !app.isTerminated {
            app.unhide()
        }
        hiddenByUs = []
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

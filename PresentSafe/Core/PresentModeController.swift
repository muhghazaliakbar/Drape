import AppKit
import Combine
import OSLog

/// Owns the on/off state of Present Mode and drives every enabled guard.
///
/// Teardown is the part that matters most here. If PresentSafe hides your
/// password manager and then crashes, the user is left with a mess they did not
/// create — so deactivation is deliberately forgiving: it runs for every guard
/// regardless of whether activation succeeded, ignores individual failures, and
/// is also invoked on app termination.
@MainActor
final class PresentModeController: ObservableObject {
    static let shared = PresentModeController()

    @Published private(set) var isActive = false
    @Published private(set) var lastError: String?

    let guards: [any PresentGuard]

    private let preferences: Preferences
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "dev.justghali.PresentSafe", category: "PresentMode")

    /// Guard ids written to disk while engaged. This is the only trace that
    /// survives a crash, and the only way the next launch can know something
    /// was left switched on.
    private static let engagedKey = "engagedGuardIDs"

    /// Guards that actually ran, so teardown only touches what was touched.
    private var engaged: [any PresentGuard] = []

    init(preferences: Preferences = .shared, defaults: UserDefaults = .standard) {
        self.preferences = preferences
        self.defaults = defaults
        self.guards = [
            HideAppsGuard(preferences: preferences),
            NotificationZoneGuard(),
            // FocusGuard(preferences: preferences),
            //   Written and working, but not shipped yet: it is useless until
            //   the user has built two Shortcuts by hand, and a protection that
            //   asks for homework before it does anything is a poor first
            //   impression. Uncomment to bring it back.
            DesktopIconsGuard(),
        ]
    }

    func toggle() {
        Task { isActive ? await deactivate() : await activate() }
    }

    func activate() async {
        guard !isActive else { return }
        lastError = nil
        engaged = []

        var failures: [String] = []
        for aGuard in guards where preferences.isEnabled(aGuard) {
            do {
                try await aGuard.activate()
                engaged.append(aGuard)
                logger.info("Engaged guard \(aGuard.id, privacy: .public)")
            } catch {
                // Record the guard as engaged anyway: activation may have applied
                // part of its change before throwing, and teardown must undo it.
                engaged.append(aGuard)
                failures.append("\(aGuard.title): \(error.localizedDescription)")
                logger.error("Guard \(aGuard.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        defaults.set(engaged.map(\.id), forKey: Self.engagedKey)
        isActive = true
        lastError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    func deactivate() async {
        for aGuard in engaged.reversed() {
            await aGuard.deactivate()
            logger.info("Released guard \(aGuard.id, privacy: .public)")
        }
        engaged = []
        defaults.removeObject(forKey: Self.engagedKey)
        isActive = false
        lastError = nil
    }

    /// Teardown used when the app is quitting.
    ///
    /// The caller is responsible for keeping the process alive until this
    /// returns — `AppDelegate` does that with `.terminateLater`. Blocking the
    /// main thread here instead would deadlock, since the guards themselves are
    /// main-actor isolated.
    func tearDownForTermination() async {
        await deactivate()
    }

    /// Undoes anything the previous run left engaged.
    ///
    /// Call once at launch, before the user can turn Present Mode on. If the
    /// marker is present, the last process died without tearing down, so every
    /// guard it had engaged gets a chance to restore itself from scratch.
    func recoverFromPreviousRun() async {
        guard let abandoned = defaults.stringArray(forKey: Self.engagedKey), !abandoned.isEmpty else { return }
        logger.notice("Previous run left guards engaged: \(abandoned.joined(separator: ", "), privacy: .public)")

        for aGuard in guards where abandoned.contains(aGuard.id) {
            await aGuard.recoverAfterUncleanShutdown()
        }
        defaults.removeObject(forKey: Self.engagedKey)
    }
}

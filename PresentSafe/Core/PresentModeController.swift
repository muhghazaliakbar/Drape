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
    private let logger = Logger(subsystem: "dev.justghali.PresentSafe", category: "PresentMode")

    /// Guards that actually ran, so teardown only touches what was touched.
    private var engaged: [any PresentGuard] = []

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        self.guards = [
            HideAppsGuard(preferences: preferences),
            NotificationZoneGuard(),
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

        isActive = true
        lastError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    func deactivate() async {
        for aGuard in engaged.reversed() {
            await aGuard.deactivate()
            logger.info("Released guard \(aGuard.id, privacy: .public)")
        }
        engaged = []
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
}

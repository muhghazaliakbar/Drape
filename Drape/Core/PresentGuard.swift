import SwiftUI

/// A single, self-contained protective action that runs while Present Mode is active.
///
/// Every capability Drape offers — hiding apps, covering the notification
/// zone, clearing the desktop — is expressed as a `PresentGuard`. The controller
/// knows nothing about what any given guard actually does; it only knows how to
/// turn guards on and back off again, in order. Adding a new protection means
/// adding one file and one line to the registry, and nothing else changes.
@MainActor
protocol PresentGuard: AnyObject {
    /// Stable identifier, used as the preferences key. Never change it once shipped.
    var id: String { get }

    /// Human-readable name shown in Settings.
    var title: String { get }

    /// One line explaining what the user gets, shown under the title.
    var summary: String { get }

    /// SF Symbol name for the Settings row.
    var symbolName: String { get }

    /// Whether this guard is safe to enable by default for a new install.
    /// Guards with visible side effects (restarting Finder, for example) say `false`.
    var isEnabledByDefault: Bool { get }

    /// Engage the protection. Throws if the protection could not be applied, in
    /// which case `deactivate()` will still be called during teardown.
    func activate() async throws

    /// Restore whatever `activate()` changed.
    ///
    /// This must be safe to call when `activate()` never ran or threw partway
    /// through — teardown happens on quit and on crash recovery, where the
    /// guard's own view of the world may be incomplete.
    func deactivate() async

    /// Called once at launch when the previous run ended while this guard was
    /// still engaged — a crash, a `kill`, a forced restart.
    ///
    /// `deactivate()` cannot cover this case: it undoes changes using state held
    /// in memory, and that state died with the process. A guard that changes
    /// anything outside its own address space must implement this and restore
    /// unconditionally, without reference to what it remembers doing.
    func recoverAfterUncleanShutdown() async

    /// Extra controls shown under this guard's row in Settings.
    ///
    /// Most guards need none. Keeping this on the protocol rather than special
    /// casing in the settings pane is what preserves the rule that adding a
    /// protection means one new file and one line in the registry.
    var configuration: AnyView? { get }
}

extension PresentGuard {
    /// Guards whose effects die with the process need no recovery.
    func recoverAfterUncleanShutdown() async {}

    var configuration: AnyView? { nil }
}

/// Errors a guard can surface to the user without taking down all of Present Mode.
enum GuardError: LocalizedError {
    case notConfigured(String)
    case systemRefused(String)

    var errorDescription: String? {
        switch self {
        // No prefix: the controller already labels the message with the
        // guard's name, and "Hide sensitive apps: Not configured yet: pick an
        // app" says the same thing three times.
        case .notConfigured(let detail): detail
        case .systemRefused(let detail): String(localized: "macOS refused the request: \(detail)")
        }
    }
}

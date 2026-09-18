import Foundation

/// A single, self-contained protective action that runs while Present Mode is active.
///
/// Every capability PresentSafe offers — hiding apps, covering the notification
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
}

/// Errors a guard can surface to the user without taking down all of Present Mode.
enum GuardError: LocalizedError {
    case notConfigured(String)
    case systemRefused(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let detail): "Not configured yet: \(detail)"
        case .systemRefused(let detail): "macOS refused the request: \(detail)"
        }
    }
}

import AppKit
import Combine

/// User-facing settings, backed by `UserDefaults`.
///
/// Guard enablement is keyed by the guard's own `id` rather than by a fixed set
/// of properties, so adding a guard needs no change here at all.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sensitiveBundleIDs = Set(defaults.stringArray(forKey: Keys.sensitiveBundleIDs) ?? Self.suggestedBundleIDs)
    }

    @Published var sensitiveBundleIDs: Set<String> {
        didSet { defaults.set(Array(sensitiveBundleIDs), forKey: Keys.sensitiveBundleIDs) }
    }

    func isEnabled(_ aGuard: any PresentGuard) -> Bool {
        defaults.object(forKey: Keys.guardEnabled(aGuard.id)) as? Bool ?? aGuard.isEnabledByDefault
    }

    func setEnabled(_ enabled: Bool, for aGuard: any PresentGuard) {
        defaults.set(enabled, forKey: Keys.guardEnabled(aGuard.id))
        objectWillChange.send()
    }

    /// A starting point so a new install is useful before the user configures
    /// anything. Only apps that are actually installed ever show up in the UI.
    static let suggestedBundleIDs: [String] = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.Passwords",
        "com.tinyspeck.slackmacgap",
        "com.apple.mail",
        "ru.keepcoder.Telegram",
        "net.whatsapp.WhatsApp",
    ]

    private enum Keys {
        static let sensitiveBundleIDs = "sensitiveBundleIDs"
        static func guardEnabled(_ id: String) -> String { "guard.\(id).enabled" }
    }
}

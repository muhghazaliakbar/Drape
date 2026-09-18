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
        self.hotKeyCombo = Self.loadCombo(from: defaults) ?? .default
    }

    @Published var sensitiveBundleIDs: Set<String> {
        didSet { defaults.set(Array(sensitiveBundleIDs), forKey: Keys.sensitiveBundleIDs) }
    }

    @Published var hotKeyCombo: KeyCombo {
        didSet {
            guard let data = try? JSONEncoder().encode(hotKeyCombo) else { return }
            defaults.set(data, forKey: Keys.hotKeyCombo)
        }
    }

    /// A stored shortcut that no longer decodes — an older build's format, or a
    /// corrupted value — falls back to the default rather than leaving the app
    /// with no shortcut at all.
    private static func loadCombo(from defaults: UserDefaults) -> KeyCombo? {
        guard let data = defaults.data(forKey: Keys.hotKeyCombo) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
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
        static let hotKeyCombo = "hotKeyCombo"
        static func guardEnabled(_ id: String) -> String { "guard.\(id).enabled" }
    }
}

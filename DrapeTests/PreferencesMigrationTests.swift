import Foundation
import Testing

@testable import Drape

/// The rename from PresentSafe to Drape changed the bundle identifier, and
/// `UserDefaults` is keyed by it. These cover the one thing that must not go
/// wrong: settings are carried over exactly once, and an install that already
/// has settings of its own is never overwritten by an old domain left on disk.
@MainActor
@Suite struct PreferencesMigrationTests {
    @Test func carriesEverySettingOverFromTheOldIdentifier() {
        withThrowawayDomains { own, legacy in
            let stored: [String: Any] = [
                "sensitiveBundleIDs": ["com.1password.1password", "com.tinyspeck.slackmacgap"],
                "keepsSensitiveAppsHidden": false,
                // Guard enablement is keyed by each guard's id, so the copy has
                // to be wholesale — a fixed list of keys would drop these.
                "guard.hideApps.enabled": true,
                "guard.notificationZone.enabled": false,
            ]
            UserDefaults.standard.setPersistentDomain(stored, forName: legacy)

            Preferences.adoptLegacySettings(into: .standard, ownDomain: own, from: legacy)

            let adopted = UserDefaults.standard.persistentDomain(forName: own) ?? [:]
            #expect(adopted.count == stored.count)
            #expect(adopted["sensitiveBundleIDs"] as? [String] == stored["sensitiveBundleIDs"] as? [String])
            #expect(adopted["keepsSensitiveAppsHidden"] as? Bool == false)
            #expect(adopted["guard.hideApps.enabled"] as? Bool == true)
            #expect(adopted["guard.notificationZone.enabled"] as? Bool == false)
        }
    }

    @Test func leavesAnInstallThatAlreadyHasSettingsAlone() {
        withThrowawayDomains { own, legacy in
            UserDefaults.standard.setPersistentDomain(["sensitiveBundleIDs": ["com.apple.mail"]], forName: own)
            UserDefaults.standard.setPersistentDomain(["sensitiveBundleIDs": ["com.stale.app"]], forName: legacy)

            Preferences.adoptLegacySettings(into: .standard, ownDomain: own, from: legacy)

            let kept = UserDefaults.standard.persistentDomain(forName: own) ?? [:]
            #expect(kept["sensitiveBundleIDs"] as? [String] == ["com.apple.mail"])
        }
    }

    @Test func doesNothingOnAMacThatNeverRanTheOldApp() {
        withThrowawayDomains { own, legacy in
            Preferences.adoptLegacySettings(into: .standard, ownDomain: own, from: legacy)

            #expect(UserDefaults.standard.persistentDomain(forName: own) == nil)
        }
    }

    /// Real domain names, so `persistentDomain` behaves as it does in the app,
    /// but random ones — the test must never read or write the settings of the
    /// app hosting it.
    private func withThrowawayDomains(_ body: (_ own: String, _ legacy: String) -> Void) {
        let run = UUID().uuidString
        let own = "dev.justghali.DrapeTests.own.\(run)"
        let legacy = "dev.justghali.DrapeTests.legacy.\(run)"
        defer {
            UserDefaults.standard.removePersistentDomain(forName: own)
            UserDefaults.standard.removePersistentDomain(forName: legacy)
        }
        body(own, legacy)
    }
}

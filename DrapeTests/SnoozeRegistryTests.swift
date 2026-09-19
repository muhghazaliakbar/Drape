import Foundation
import Testing

@testable import Drape

@Suite("Snooze")
@MainActor
struct SnoozeRegistryTests {

    private let app = "com.example.Chat"
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("An app nobody snoozed is not snoozed")
    func unknownAppIsNotSnoozed() {
        #expect(SnoozeRegistry().isSnoozed(app, now: now) == false)
    }

    @Test("Snoozing holds for the full duration")
    func holdsForTheDuration() {
        let registry = SnoozeRegistry()
        registry.snooze(app, now: now)

        #expect(registry.isSnoozed(app, now: now))
        #expect(registry.isSnoozed(app, now: now.addingTimeInterval(SnoozeRegistry.duration - 1)))
    }

    @Test("And expires exactly when it should")
    func expiresOnTime() {
        let registry = SnoozeRegistry()
        registry.snooze(app, now: now)

        // Protection coming back a moment late is a leak, so the boundary is
        // closed rather than open.
        #expect(registry.isSnoozed(app, now: now.addingTimeInterval(SnoozeRegistry.duration)) == false)
        #expect(registry.isSnoozed(app, now: now.addingTimeInterval(SnoozeRegistry.duration + 60)) == false)
    }

    @Test("Snoozing one app does not snooze another")
    func snoozeIsPerApp() {
        let registry = SnoozeRegistry()
        registry.snooze(app, now: now)
        #expect(registry.isSnoozed("com.example.Mail", now: now) == false)
    }

    @Test("Snoozing again extends from the new moment")
    func reSnoozingExtends() {
        let registry = SnoozeRegistry()
        registry.snooze(app, now: now)
        let later = now.addingTimeInterval(SnoozeRegistry.duration - 10)
        registry.snooze(app, now: later)

        #expect(registry.isSnoozed(app, now: later.addingTimeInterval(SnoozeRegistry.duration - 1)))
    }

    @Test("Remaining time counts down and never goes negative")
    func remainingIsClamped() {
        let registry = SnoozeRegistry()
        registry.snooze(app, now: now)

        #expect(registry.remaining(app, now: now) == SnoozeRegistry.duration)
        #expect(registry.remaining(app, now: now.addingTimeInterval(SnoozeRegistry.duration + 500)) == 0)
    }

    @Test("Clearing ends every snooze")
    func clearingEndsEverything() {
        let registry = SnoozeRegistry()
        registry.snooze(app, now: now)
        registry.clear()
        #expect(registry.isSnoozed(app, now: now) == false)
    }
}

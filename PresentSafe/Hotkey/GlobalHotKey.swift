import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut.
///
/// This goes through Carbon's `RegisterEventHotKey` rather than
/// `NSEvent.addGlobalMonitorForEvents`, because the NSEvent route requires
/// Accessibility permission and this one does not. PresentSafe is a tool you
/// reach for *seconds* before you start sharing, so a shortcut that works
/// immediately after install matters more than using a modern API.
@MainActor
final class GlobalHotKey {
    enum RegistrationError: LocalizedError {
        /// `eventHotKeyExistsErr`. Verified behaviour: this fires only for a
        /// duplicate registration *inside one process* — two separate apps can
        /// both register the same combination and macOS reports no conflict to
        /// either of them. So this is a bug guard, not a "taken by another app"
        /// signal; there is no API that provides one.
        case duplicateRegistration
        case failed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .duplicateRegistration:
                "This shortcut is already registered. Try a different one."
            case .failed(let status):
                "macOS refused to register this shortcut (error \(status))."
            }
        }
    }

    private let handles = CarbonHotKeyHandles()
    private let identifier: UInt32

    init(identifier: UInt32 = 1) {
        self.identifier = identifier
    }

    /// Claims `combo` system-wide. Any previous registration is released first,
    /// so this doubles as the re-registration path when the user picks a new
    /// shortcut.
    func register(_ combo: KeyCombo, action: @escaping () -> Void) throws {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, nil, &handles.handler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x50534146 /* "PSAF" */), id: identifier)
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &handles.hotKey
        )

        guard status == noErr else {
            // Leave nothing half-registered behind: a stale event handler with
            // no hot key would keep the old shortcut alive invisibly.
            unregister()
            throw status == OSStatus(eventHotKeyExistsErr) ? RegistrationError.duplicateRegistration : .failed(status)
        }

        hotKeyActions[identifier] = action
    }

    func unregister() {
        hotKeyActions[identifier] = nil
        handles.release()
    }
}

/// Owns the two opaque Carbon handles.
///
/// Carbon predates Swift concurrency, so `EventHotKeyRef` and `EventHandlerRef`
/// are bare `OpaquePointer`s that Swift 6 will not let a `deinit` touch from an
/// actor-isolated type. Boxing them here moves cleanup into a plain reference
/// type, which can release them on the way out without any isolation at all.
private final class CarbonHotKeyHandles: @unchecked Sendable {
    var hotKey: EventHotKeyRef?
    var handler: EventHandlerRef?

    func release() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    deinit { release() }
}

/// Carbon hands control back through a bare C function pointer, which cannot
/// capture context — so the callbacks live here, keyed by hot key id. Carbon
/// dispatches on the main thread, which is what makes the isolation below sound.
@MainActor private var hotKeyActions: [UInt32: () -> Void] = [:]

private let hotKeyEventHandler: EventHandlerUPP = { _, event, _ in
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    MainActor.assumeIsolated {
        hotKeyActions[hotKeyID.id]?()
    }
    return noErr
}

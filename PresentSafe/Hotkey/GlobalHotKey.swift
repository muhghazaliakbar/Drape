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
    /// Control-Option-Command-P: deliberately awkward, because the cost of
    /// triggering this by accident mid-presentation is higher than the cost of
    /// a four-finger chord.
    static let defaultKeyCode = UInt32(kVK_ANSI_P)
    static let defaultModifiers = UInt32(controlKey | optionKey | cmdKey)

    private let handles = CarbonHotKeyHandles()
    private let identifier: UInt32

    init(identifier: UInt32 = 1) {
        self.identifier = identifier
    }

    func register(
        keyCode: UInt32 = GlobalHotKey.defaultKeyCode,
        modifiers: UInt32 = GlobalHotKey.defaultModifiers,
        action: @escaping () -> Void
    ) {
        unregister()
        hotKeyActions[identifier] = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, nil, &handles.handler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x50534146 /* "PSAF" */), id: identifier)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &handles.hotKey)
    }

    func unregister() {
        hotKeyActions[identifier] = nil
        handles.release()
    }

    /// A readable rendering of the default shortcut, for the menu and Settings.
    static var defaultDisplayString: String { "⌃⌥⌘P" }
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

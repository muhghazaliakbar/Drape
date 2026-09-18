import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A click-to-record shortcut field.
///
/// Recording a global shortcut has two traps, both handled here:
///
/// 1. The existing shortcut has to be released first, or pressing it to
///    re-record simply fires it instead (`HotKeyCenter.suspend()`).
/// 2. Anything with ⌘ in it is claimed by `performKeyEquivalent` before
///    `keyDown` ever runs, so a recorder that only overrides `keyDown` silently
///    fails to capture the most common shortcuts of all.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo

    @State private var isRecording = false
    @State private var liveModifiers: NSEvent.ModifierFlags = []
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Button(action: toggleRecording) {
                token
            }
            .buttonStyle(.plain)
            .overlay {
                if isRecording {
                    KeyCaptureView(
                        onKeyDown: handleKeyDown,
                        onModifiersChanged: { liveModifiers = $0 },
                        onCancel: stopRecording
                    )
                    .frame(width: 0, height: 0)
                }
            }

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Without this the button stretches to fill the width `LabeledContent`
        // hands its trailing view, leaving a short chord marooned in the middle
        // of a very wide control.
        .fixedSize()
    }

    /// The shortcut drawn as a key cap.
    private var token: some View {
        HStack(spacing: 4) {
            if isRecording && liveModifiers.isEmpty {
                Text("Type a shortcut")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleSymbols, id: \.self) { symbol in
                    Text(symbol)
                }
                if !isRecording {
                    Text(combo.keyLabel)
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .frame(minWidth: 84)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isRecording ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(Color(nsColor: .quaternarySystemFill)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: 1
                )
        )
        .contentShape(.rect)
    }

    private var visibleSymbols: [String] {
        isRecording ? KeyCombo.symbols(for: liveModifiers) : combo.modifierSymbols
    }

    private var caption: String? {
        if let hint { return hint }
        return isRecording ? "⎋ cancel · ⌫ reset" : nil
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        hint = nil
        liveModifiers = []
        HotKeyCenter.shared.suspend()
        isRecording = true
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        liveModifiers = []
        HotKeyCenter.shared.resume()
    }

    /// Returns `true` when the event was consumed, which keeps it from leaking
    /// out to the rest of the app while recording.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if event.keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
            stopRecording()
            return true
        }

        if event.keyCode == UInt16(kVK_Delete), modifiers.isEmpty {
            combo = .default
            stopRecording()
            return true
        }

        let candidate = KeyCombo(keyCode: event.keyCode, modifiers: modifiers)

        if let shadowed = candidate.shadowedSystemShortcut {
            hint = "That would take \(shadowed) away from every app."
            return true
        }

        guard candidate.isValid else {
            // Stay in recording mode: the user is mid-chord, or tried a bare
            // key that would swallow their typing system-wide.
            hint = "Include ⌘, ⌥ or ⌃."
            return true
        }

        combo = candidate
        hint = nil
        stopRecording()
        return true
    }
}

/// A zero-size view whose only job is to be first responder and forward raw key
/// events while the recorder is active.
private struct KeyCaptureView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool
    let onModifiersChanged: (NSEvent.ModifierFlags) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = onKeyDown
        view.onModifiersChanged = onModifiersChanged
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: KeyCaptureNSView, context: Context) {
        view.onKeyDown = onKeyDown
        view.onModifiersChanged = onModifiersChanged
        view.onCancel = onCancel
    }
}

private final class KeyCaptureNSView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onModifiersChanged: ((NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // Deferred, because SwiftUI may still be settling the responder chain
        // on the turn this view is inserted.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    /// The important override. Menu key equivalents are dispatched here first,
    /// so anything containing ⌘ arrives through this method and never reaches
    /// `keyDown(with:)`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onKeyDown?(event) ?? false
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        onModifiersChanged?(event.modifierFlags.intersection([.command, .option, .control, .shift]))
        super.flagsChanged(with: event)
    }

    override func resignFirstResponder() -> Bool {
        onCancel?()
        return super.resignFirstResponder()
    }
}

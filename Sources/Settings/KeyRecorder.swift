import AppKit
import SwiftUI

/// Button-shaped SwiftUI control that captures a single keyboard
/// shortcut. Click the button to enter listen mode, then press any
/// key combo; Esc cancels without changing the current binding.
/// Delete / Backspace clears the binding (via `onClear`) — falling
/// back to `onCancel` when `onClear` is not provided.
/// `Set shortcut…` placeholder appears while `spec` is `nil`.
struct KeyRecorder: View {

    @Binding var spec: ShortcutSpec?
    var placeholder: String = "Set shortcut…"
    /// When `true`, starts listening the first time the view appears —
    /// used by the Saved-snap inline editor so the user doesn't have
    /// to click the recorder itself after clicking the keycap.
    var autoStart: Bool = false
    /// Fired when the user presses Esc instead of a shortcut. Lets the
    /// parent exit an inline-edit mode and restore whatever UI was
    /// showing before (e.g. the saved `KeycapView`).
    var onCancel: (() -> Void)? = nil
    /// Fired when the user presses Delete / Backspace — matches the
    /// macOS System Settings convention where that gesture unbinds
    /// the shortcut. If `nil`, Delete behaves like Esc (cancel).
    var onClear: (() -> Void)? = nil

    @State private var isListening = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleListening) {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isListening ? Color.accentColor : .primary)
                .frame(minWidth: 140, alignment: .center)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
        }
        .buttonStyle(.bordered)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isListening ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .task {
            if autoStart { beginListening() }
        }
        .onDisappear { stopListening() }
    }

    private var label: String {
        if isListening { return "Press shortcut…" }
        if let spec { return spec.displayString }
        return placeholder
    }

    // MARK: - Listening lifecycle

    private func toggleListening() {
        if isListening {
            stopListening()
        } else {
            beginListening()
        }
    }

    private func beginListening() {
        stopListening()
        isListening = true
        ShortcutRecordingGate.shared.beginRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event: event)
        }
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isListening = false
        ShortcutRecordingGate.shared.endRecording()
    }

    /// Returns `nil` to swallow the event so the captured shortcut
    /// doesn't leak into the focused control.
    private func handle(event: NSEvent) -> NSEvent? {
        // Esc cancels without recording.
        if event.keyCode == 53 {
            stopListening()
            onCancel?()
            return nil
        }
        // Delete (⌫ 51) / Forward-Delete (⌦ 117) unbinds the shortcut.
        // Matches macOS System Settings behavior for keyboard shortcut
        // recorders. Falls back to cancel when no handler is wired.
        if event.keyCode == 51 || event.keyCode == 117 {
            stopListening()
            if let onClear { onClear() } else { onCancel?() }
            return nil
        }
        // macOS auto-sets the fn bit on arrow-key presses (legacy quirk
        // from old MacBook keyboards). Strip it so `⇧⌥←` isn't saved
        // as `fn⇧⌥←` and fail to match at event-tap time.
        let mods = PressedModifiers(nsFlags: event.modifierFlags)
            .subtracting(.function)
        spec = ShortcutSpec(keyCode: Int64(event.keyCode), modifiers: mods)
        stopListening()
        return nil
    }
}

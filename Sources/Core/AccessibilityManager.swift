@preconcurrency import Cocoa
import Observation

@Observable @MainActor
final class AccessibilityManager {
    static let shared = AccessibilityManager()

    private(set) var isTrusted: Bool = false
    private(set) var canListenEvents: Bool = false

    /// Single observer slot, invoked on the main actor after permission
    /// values are refreshed. AppDelegate uses it to start the coordinators
    /// once permissions arrive; `DragCoordinator.start()` then takes the
    /// slot over for menu-bar error display. Last writer wins by design.
    @ObservationIgnored var onPermissionsChange: ((AccessibilityManager) -> Void)?

    // MARK: - Permission polling

    @ObservationIgnored private var pollingTimer: Timer?

    var allPermissionsGranted: Bool {
        isTrusted && canListenEvents
    }

    func checkPermission() {
        isTrusted = AXIsProcessTrusted()
        canListenEvents = checkInputMonitoring()
        onPermissionsChange?(self)
    }

    func requestPermission() {
        isTrusted = AXIsProcessTrusted()
        if !isTrusted {
            openAccessibilitySettings()
        }
    }

    /// Opens System Settings to the Accessibility pane.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens System Settings to the Input Monitoring pane.
    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Checks if Input Monitoring permission is granted.
    private func checkInputMonitoring() -> Bool {
        return CGPreflightListenEventAccess()
    }

    /// Begins polling every `interval` seconds, publishing changes.
    /// Stops automatically once all permissions are granted.
    func startPolling(interval: TimeInterval = 2.0) {
        guard pollingTimer == nil else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let trusted = AXIsProcessTrusted()
                let listen = self.checkInputMonitoring()
                let changed = trusted != self.isTrusted || listen != self.canListenEvents
                self.isTrusted = trusted
                self.canListenEvents = listen
                if changed {
                    self.onPermissionsChange?(self)
                }
                if trusted && listen {
                    self.stopPolling()
                }
            }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}

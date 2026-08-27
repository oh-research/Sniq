import Cocoa
import os

/// Unified logger for Sniq. Debug-level messages do not persist to disk;
/// to stream them live during development, run:
///
///     log stream --predicate 'subsystem == "com.ohresearch.sniq"' --level debug
private let appLogger = Logger(subsystem: "com.ohresearch.sniq", category: "Sniq")

/// Emits a debug message via the unified logging system.
///
/// Replaces the previous file-based logger that wrote to `~/sniq-debug.log`
/// on every call — that approach bloated the user's home directory in release
/// builds. `os.Logger.debug` messages are not persisted unless a caller is
/// actively streaming them (via `log stream` or Console.app).
func debugLog(_ msg: String) {
    appLogger.debug("\(msg, privacy: .public)")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusBarController = StatusBarController()
    private let dragCoordinator = DragCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("[Sniq] launched")
        // Wake the lazy store so SnapLookupMirror is populated before the
        // first shortcut key event; otherwise saved snaps stay dead until
        // the Snaps window is opened.
        _ = SnapStore.shared
        statusBarController.setup()
        dragCoordinator.statusBarController = statusBarController

        if PreferencesStore.shared.onboardingCompleted {
            AccessibilityManager.shared.checkPermission()
        }
        debugLog("[Sniq] Accessibility trusted: \(AccessibilityManager.shared.isTrusted)")

        debugLog("[Sniq] onboardingCompleted: \(PreferencesStore.shared.onboardingCompleted), allPermissionsGranted: \(AccessibilityManager.shared.allPermissionsGranted)")
        if !PreferencesStore.shared.onboardingCompleted || !AccessibilityManager.shared.allPermissionsGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                statusBarController.showOnboarding()
            }
        }

        if AccessibilityManager.shared.allPermissionsGranted {
            debugLog("[Sniq] Starting DragCoordinator")
            dragCoordinator.start()
        } else {
            debugLog("[Sniq] Waiting for permissions")
            AccessibilityManager.shared.startPolling()
            // start() re-points onPermissionsChange to error display, so
            // this fires effectively once.
            AccessibilityManager.shared.onPermissionsChange = { [weak self] manager in
                guard manager.allPermissionsGranted else { return }
                self?.dragCoordinator.start()
            }
        }
    }
}

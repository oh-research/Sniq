import ServiceManagement

/// Wraps SMAppService to read and toggle the app's login-item registration.
@MainActor
enum LoginItemHelper {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Sets the login item state to `enabled`. Failures are silent — the
    /// Settings toggle simply reads back the unchanged status.
    static func setEnabled(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}

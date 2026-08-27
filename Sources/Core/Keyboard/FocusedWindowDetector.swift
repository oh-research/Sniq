@preconcurrency import Cocoa
import ApplicationServices

/// Queries the accessibility tree for the currently focused window of the
/// frontmost application.
enum FocusedWindowDetector {

    /// Returns the focused window of the frontmost application, or `nil`
    /// if no window is available (Finder desktop focus, permission denied,
    /// app genuinely has no window, etc.).
    ///
    /// Strategy: the system-wide `kAXFocusedApplicationAttribute` is the
    /// fast path, but Electron apps (VS Code, Slack, etc.) intermittently
    /// return `kAXErrorNoValue` for that attribute even while being
    /// NSWorkspace-frontmost. When that happens we fall back to building
    /// the AXApplication directly from `NSWorkspace.frontmostApplication`'s
    /// PID — `AXUIElementCreateApplication` is always valid regardless of
    /// whether the process has published itself system-wide.
    static func focusedWindow() -> AXUIElement? {
        guard let app = focusedApplicationElement() else { return nil }
        AXUIElementSetMessagingTimeout(app, 0.1)

        var focusedWindow: CFTypeRef?
        let winResult = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard winResult == .success, let window = focusedWindow else {
            logFailure(stage: "focusedWindow", error: winResult)
            return nil
        }
        return (window as! AXUIElement)
    }

    /// Resolves the AXApplication element for the frontmost app, falling
    /// back from the system-wide query to a PID-based construction when
    /// the former returns no value (Electron quirk).
    private static func focusedApplicationElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.1)

        var focusedApp: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        if appResult == .success, let app = focusedApp {
            return (app as! AXUIElement)
        }
        logFailure(stage: "focusedApp", error: appResult)

        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        return AXUIElementCreateApplication(pid)
    }

    /// Emits a diagnostic entry when an AX lookup for the focused window
    /// fails. The frontmost bundle identifier is included so per-app
    /// regressions (e.g. Electron apps) can be isolated in Console.app.
    private static func logFailure(stage: String, error: AXError) {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        debugLog("[FocusedWindow] \(stage) failed: ax=\(error.rawValue) frontmost=\(bundleID)")
    }

    /// Reads the frame (position + size) of the given AX window element in
    /// CG coordinates (top-left origin). Returns `nil` if either attribute
    /// is missing or malformed.
    ///
    /// Uses `AXUIElementCopyMultipleAttributeValues` to fetch both values
    /// in a single AX IPC round-trip instead of two sequential calls —
    /// saves 20-80 ms per snap on slow-AX apps (Electron, etc.).
    static func frame(of element: AXUIElement) -> CGRect? {
        let attrs = [kAXPositionAttribute, kAXSizeAttribute] as CFArray
        var valuesRef: CFArray?
        // `.stopOnError` guarantees that if either attribute fails, the
        // call returns a non-`.success` status instead of silently writing
        // an `AXError` CFNumber into the result array (which we would
        // then reinterpret as an `AXValue` — undefined behavior).
        let status = AXUIElementCopyMultipleAttributeValues(
            element, attrs, .stopOnError, &valuesRef
        )
        guard status == .success,
              let valuesRef,
              CFArrayGetCount(valuesRef) == 2,
              let posRaw = CFArrayGetValueAtIndex(valuesRef, 0),
              let sizRaw = CFArrayGetValueAtIndex(valuesRef, 1)
        else { return nil }

        let pos = Unmanaged<AXValue>.fromOpaque(posRaw).takeUnretainedValue()
        let siz = Unmanaged<AXValue>.fromOpaque(sizRaw).takeUnretainedValue()

        var cgPosition = CGPoint.zero
        var cgSize = CGSize.zero
        guard AXValueGetType(pos) == .cgPoint,
              AXValueGetValue(pos, .cgPoint, &cgPosition),
              AXValueGetType(siz) == .cgSize,
              AXValueGetValue(siz, .cgSize, &cgSize)
        else { return nil }

        return CGRect(origin: cgPosition, size: cgSize)
    }

    /// Returns the NSScreen whose visible frame contains the center of
    /// `frame` (CG coordinates). Falls back to `NSScreen.main` if no
    /// screen contains the point.
    @MainActor
    static func screen(containing frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        for screen in NSScreen.screens where screen.visibleFrameCG.contains(center) {
            return screen
        }
        return NSScreen.main
    }

}

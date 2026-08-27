@preconcurrency import Cocoa

// MARK: - WindowInfo

struct WindowInfo: @unchecked Sendable {
    let windowID: CGWindowID   // 0 if unknown
    let pid: pid_t
    let frame: CGRect          // CG coordinate system (top-left origin)
    let title: String
    let axElement: AXUIElement
    let isFullscreen: Bool
}


// MARK: - WindowDetector

/// Detects the window under a given screen-space point using:
///   1. AXUIElementCopyElementAtPosition  (primary)
///   2. CGWindowListCopyWindowInfo        (fallback)
///
/// All methods are safe to call off the main thread.
final class WindowDetector: Sendable {

    static let shared = WindowDetector()

    // MARK: - Public API

    /// Returns the window at `point` (CG coordinate system).
    /// Returns nil if no window found or AX permission is unavailable.
    func windowAtPoint(_ point: CGPoint) -> WindowInfo? {
        // Primary: AX tree walk
        if let info = windowViaAX(at: point) {
            return info
        }
        // Fallback: CGWindowList
        return windowViaCGWindowList(at: point)
    }

    // MARK: - AX primary path

    private func windowViaAX(at point: CGPoint) -> WindowInfo? {
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWide, Float(point.x), Float(point.y), &elementRef
        )
        guard result == .success, let element = elementRef else { return nil }

        guard let windowElement = walkToWindow(from: element) else { return nil }

        return buildWindowInfo(from: windowElement, cursorPoint: point)
    }

    /// Walk the AX parent chain until we reach an AXWindow role (max 10 steps).
    private func walkToWindow(from element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<10 {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleRef)
            if let role = roleRef as? String, role == (kAXWindowRole as String) {
                return current
            }
            var parentRef: CFTypeRef?
            let pr = AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef)
            guard pr == .success, let parent = parentRef else { return nil }
            current = parent as! AXUIElement
        }
        return nil
    }

    private func buildWindowInfo(from windowElement: AXUIElement, cursorPoint: CGPoint) -> WindowInfo? {
        // Position
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef)

        var pos = CGPoint.zero
        var size = CGSize.zero
        if let p = posRef { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
        if let s = sizeRef { AXValueGetValue(s as! AXValue, .cgSize, &size) }

        guard size.width > 0 && size.height > 0 else { return nil }

        // Title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? ""

        // PID
        var pid: pid_t = 0
        AXUIElementGetPid(windowElement, &pid)

        let frame = CGRect(origin: pos, size: size)

        // Check fullscreen via AX attribute, then fallback to frame == screen frame
        let isFullscreen = checkFullscreen(element: windowElement, frame: frame)

        return WindowInfo(
            windowID: 0,
            pid: pid,
            frame: frame,
            title: title,
            axElement: windowElement,
            isFullscreen: isFullscreen
        )
    }

    private func checkFullscreen(element: AXUIElement, frame: CGRect) -> Bool {
        // Primary: AXFullScreen attribute (string literal; kAXFullScreenAttribute is unavailable in Swift)
        var fsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &fsRef)
        if let fsVal = fsRef as? Bool {
            return fsVal
        }
        // Fallback: window frame equals a screen frame
        for screen in NSScreen.screens {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let screenCGFrame = CGRect(
                x: screen.frame.origin.x,
                y: primaryHeight - screen.frame.origin.y - screen.frame.height,
                width: screen.frame.width,
                height: screen.frame.height
            )
            if frame == screenCGFrame {
                return true
            }
        }
        return false
    }

    // MARK: - CGWindowList fallback

    private func windowViaCGWindowList(at point: CGPoint) -> WindowInfo? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for window in list {
            guard
                let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                let x = bounds["X"], let y = bounds["Y"],
                let w = bounds["Width"], let h = bounds["Height"]
            else { continue }

            let rect = CGRect(x: x, y: y, width: w, height: h)
            guard rect.contains(point) else { continue }

            let ownerPID = (window[kCGWindowOwnerPID as String] as? Int).map { pid_t($0) } ?? 0
            let title = (window[kCGWindowName as String] as? String) ?? ""

            let appElement = AXUIElementCreateApplication(ownerPID)
            guard let windowElement = axWindow(from: appElement, matchingFrame: rect) else { continue }

            let isFullscreen = checkFullscreen(element: windowElement, frame: rect)

            return WindowInfo(
                windowID: 0,
                pid: ownerPID,
                frame: rect,
                title: title,
                axElement: windowElement,
                isFullscreen: isFullscreen
            )
        }
        return nil
    }

    // MARK: - AX window lookup by frame

    /// Finds the AX window element whose frame matches `targetFrame` within a
    /// few points. CGWindowList bounds and AX position/size agree up to
    /// sub-pixel rounding, so a 2pt tolerance is enough to disambiguate.
    private func axWindow(from appElement: AXUIElement, matchingFrame targetFrame: CGRect) -> AXUIElement? {
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement] else { return nil }

        for window in windows {
            guard let frame = axFrame(of: window) else { continue }
            if framesMatch(frame, targetFrame, tolerance: 2) {
                return window
            }
        }
        return nil
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        var pos = CGPoint.zero
        var size = CGSize.zero
        guard let p = posRef, AXValueGetValue(p as! AXValue, .cgPoint, &pos) else { return nil }
        guard let s = sizeRef, AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    private func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance &&
            abs(a.minY - b.minY) <= tolerance &&
            abs(a.width - b.width) <= tolerance &&
            abs(a.height - b.height) <= tolerance
    }
}

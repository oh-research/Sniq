import Cocoa

extension NSScreen {
    /// The CoreGraphics display ID for this screen.
    var displayID: CGDirectDisplayID? {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return id
    }
}

extension CGRect {
    /// Whether origin and size both match `other` within `tolerance`
    /// points per component — loose enough to absorb AX rounding after
    /// a previous snap.
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

extension NSScreen {
    /// NSScreen.visibleFrame (bottom-left Cocoa origin) converted to the
    /// CG coordinate space (top-left origin).
    var visibleFrameCG: CGRect {
        guard let primary = NSScreen.screens.first else { return visibleFrame }
        let primaryHeight = primary.frame.height
        return CGRect(
            x: visibleFrame.origin.x,
            y: primaryHeight - visibleFrame.origin.y - visibleFrame.height,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }

    /// NSScreen.frame (full screen including menu bar) converted to the
    /// CG coordinate space (top-left origin).
    var fullFrameCG: CGRect {
        guard let primary = NSScreen.screens.first else { return frame }
        let primaryHeight = primary.frame.height
        return CGRect(
            x: frame.origin.x,
            y: primaryHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }
}

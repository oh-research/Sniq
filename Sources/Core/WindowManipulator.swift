@preconcurrency import Cocoa

// MARK: - WindowManipulator

/// Moves and resizes windows by writing AX attributes.
/// All methods are safe to call from any thread.
final class WindowManipulator: Sendable {

    static let shared = WindowManipulator()

    // MARK: - Public API

    /// Moves and resizes `element` to `frame` (CG coordinate system).
    /// Returns true on success.
    ///
    /// Order: size → position → size. The first size lets the window
    /// shrink to fit (respecting any minimum-size constraint) before
    /// the move, preventing the window from overflowing the target
    /// cell while still at its original dimensions. Position then
    /// moves the (possibly-resized) window. The final size re-applies
    /// because several apps — observed in the wild on cross-monitor
    /// snaps — reset their size back to the pre-move value during the
    /// position change. Costs one extra AX round-trip (5–15 ms on
    /// slow apps) but is worth it for a crisp, single-step snap.
    ///
    /// No pre-validation: a closed / invalid element fails the AX
    /// writes synchronously and returns `false`, avoiding an extra
    /// AX round-trip on every snap.
    @discardableResult
    func setFrame(_ frame: CGRect, for element: AXUIElement) -> Bool {
        _ = writeSize(frame.size, for: element)
        let posOK = writePosition(frame.origin, for: element)
        let sizeOK = writeSize(frame.size, for: element)
        return posOK && sizeOK
    }

    // MARK: - Private helpers

    private func writePosition(_ position: CGPoint, for element: AXUIElement) -> Bool {
        var point = position
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    private func writeSize(_ size: CGSize, for element: AXUIElement) -> Bool {
        var sz = size
        guard let value = AXValueCreate(.cgSize, &sz) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }
}

@preconcurrency import Cocoa

/// Routes key-down events to saved `Snap`s. Match happens in the
/// `CGEventTap` callback via `SnapStore.lookup` (lock-protected),
/// then the actual window move hops to the main actor.
///
/// Lifecycle: `DragCoordinator.start()` calls `wire(to:)` — this installs
/// the keyboard handler on the shared `EventMonitor` and starts the
/// `FocusedWindowCache` helper. `DragCoordinator.stop()` calls
/// `unwire(from:)` to tear those down symmetrically.
final class CustomSnapCoordinator: @unchecked Sendable {

    static let shared = CustomSnapCoordinator()

    private init() {}

    // MARK: - Wiring

    func wire(to monitor: EventMonitor) {
        FocusedWindowCache.shared.start()
        monitor.keyboardHandler = { [weak self] keyCode, modifiers in
            guard let self else { return false }
            return self.shouldSuppress(keyCode: keyCode, modifiers: modifiers)
        }
    }

    @MainActor
    func unwire(from monitor: EventMonitor) {
        monitor.keyboardHandler = nil
        FocusedWindowCache.shared.stop()
    }

    // MARK: - Event-tap entry

    /// Returns `true` when Sniq claims the key event (suppress); `false`
    /// to pass it through. Runs on the tap callback thread — every branch
    /// must return within the ~1 ms budget.
    private func shouldSuppress(keyCode: Int64, modifiers: PressedModifiers) -> Bool {
        guard !PauseState.isPaused else { return false }
        // macOS flips the fn bit on arrow-key events even when the user
        // hasn't touched fn; strip it so stored shortcuts match.
        let normalized = modifiers.subtracting(.function)
        // Only log modifier-bearing keyDowns — plain typing is not a
        // snap candidate and would flood the trace.
        let diag = !normalized.isEmpty

        // Settings' KeyRecorder needs the raw key event. Yield so the
        // recorded combo doesn't trigger a previously-bound snap.
        if ShortcutRecordingGate.shared.isRecording {
            if diag { debugLog("[snap] key=\(keyCode) mods=\(normalized.formatted) gate=recording → pass") }
            return false
        }
        guard let snap = SnapLookupMirror.shared.lookup(
            keyCode: keyCode, modifiers: normalized
        ) else {
            if diag { debugLog("[snap] key=\(keyCode) mods=\(normalized.formatted) → no match, pass") }
            return false
        }
        guard let window = FocusedWindowCache.shared.focusedWindow else {
            debugLog("[snap] key=\(keyCode) mods=\(normalized.formatted) matched→\(snap.spec.summary) no-focus-window → pass")
            return false
        }
        debugLog("[snap] key=\(keyCode) mods=\(normalized.formatted) matched→\(snap.spec.summary) → suppress")
        DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
            self?.performSnap(snap: snap, window: window)
        }
        return true
    }

    // MARK: - Snap execution (main actor)

    /// The most recent keyboard snap. Cycling is a repeat-press gesture:
    /// only the same shortcut on the same window, still sitting where the
    /// previous press put it, advances along the strip. Geometry alone
    /// can't tell "already snapped left" from a full-size window that
    /// merely shares the left edge, so a first press always lands on the
    /// snap's own region.
    private struct LastPlacement {
        let snapID: UUID
        let window: AXUIElement
        let ringIndex: Int
        let rect: CGRect

        func isRepeat(of snap: Snap, on window: AXUIElement, currentFrame: CGRect) -> Bool {
            // Match origin plus the cross-axis size only: an app whose
            // minimum size exceeds one cell clamps the along-axis
            // dimension, and a full-frame comparison would strand cycling.
            let isHorizontalStrip = snap.spec.rows == 1
            let crossAxisMatches = isHorizontalStrip
                ? abs(currentFrame.height - rect.height) <= 2
                : abs(currentFrame.width - rect.width) <= 2
            return snapID == snap.id
                && CFEqual(self.window, window)
                && currentFrame.origin.isApproximatelyEqual(to: rect.origin)
                && crossAxisMatches
        }
    }

    @MainActor
    private var lastPlacement: LastPlacement?

    @MainActor
    private func performSnap(snap: Snap, window: AXUIElement) {
        guard let currentFrame = FocusedWindowDetector.frame(of: window) else {
            FocusedWindowCache.shared.invalidate()
            return
        }
        guard let screen = FocusedWindowDetector.screen(containing: currentFrame) else { return }
        guard var target = targetRect(for: snap.spec, on: screen) else { return }

        // Repeat-press cycling on strip grids (1×n / n×1): advance one
        // step in the snap's anchored direction (a left/top snap keeps
        // moving left/up, wrapping to the far end).
        var ringIndex = 0
        let ringRects = snap.spec.stripCycle().compactMap { targetRect(for: $0, on: screen) }
        if ringRects.count > 1,
           let last = lastPlacement,
           last.isRepeat(of: snap, on: window, currentFrame: currentFrame) {
            ringIndex = (last.ringIndex + 1) % ringRects.count
            target = ringRects[ringIndex]
        }

        WindowManipulator.shared.setFrame(target, for: window)
        lastPlacement = LastPlacement(snapID: snap.id, window: window, ringIndex: ringIndex, rect: target)
    }

    /// Resolves a spec's region to screen coordinates using the user's
    /// current gap/padding. Returns `nil` when the spec's cells fall
    /// outside its own grid (corrupt import, hand-edited file).
    @MainActor
    private func targetRect(for spec: SnapSpec, on screen: NSScreen) -> CGRect? {
        let prefs = PreferencesStore.shared
        let config = GridConfiguration(
            rows: spec.rows,
            cols: spec.cols,
            gap: CGFloat(prefs.gap),
            padding: CGFloat(prefs.padding)
        )
        let cells = GridCalculator.cells(
            for: screen.visibleFrameCG, configuration: config
        )
        guard
            spec.minCell.row >= 0, spec.minCell.col >= 0,
            spec.maxCell.row < cells.count,
            !cells.isEmpty,
            spec.maxCell.col < cells[0].count
        else { return nil }

        return cells[spec.minCell.row][spec.minCell.col]
            .union(cells[spec.maxCell.row][spec.maxCell.col])
    }
}

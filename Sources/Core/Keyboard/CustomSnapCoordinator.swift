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

    @MainActor
    private func performSnap(snap: Snap, window: AXUIElement) {
        guard let currentFrame = FocusedWindowDetector.frame(of: window) else {
            FocusedWindowCache.shared.invalidate()
            return
        }
        guard let screen = FocusedWindowDetector.screen(containing: currentFrame) else { return }
        guard var target = targetRect(for: snap.spec, on: screen) else { return }

        // Repeat-press cycling on strip grids (1×n / n×1): when the
        // window already sits at any placement of this snap's ring,
        // advance one step in the snap's anchored direction (a left/top
        // snap keeps moving left/up, wrapping to the far end).
        //
        // Slot occupancy matches origin plus the cross-axis size only:
        // an app whose minimum size exceeds one cell clamps the along-
        // axis dimension (e.g. width on a small screen's 1×3), and a
        // full-frame comparison would strand cycling at the first slot.
        let ringRects = snap.spec.stripCycle().compactMap { targetRect(for: $0, on: screen) }
        if ringRects.count > 1 {
            let isHorizontalStrip = snap.spec.rows == 1
            let position = ringRects.firstIndex { slot in
                currentFrame.origin.isApproximatelyEqual(to: slot.origin)
                    && (isHorizontalStrip
                        ? abs(currentFrame.height - slot.height) <= 2
                        : abs(currentFrame.width - slot.width) <= 2)
            }
            if let position {
                target = ringRects[(position + 1) % ringRects.count]
            }
        }

        WindowManipulator.shared.setFrame(target, for: window)
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

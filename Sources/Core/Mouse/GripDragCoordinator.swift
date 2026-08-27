@preconcurrency import Cocoa
import ApplicationServices
import os

/// Grip+drag gesture: hold Grip (default ⇧) + click-drag anywhere on a
/// window → snap on drop. Flip (⌃) swaps layouts; Stretch (⌥) toggles
/// multi-cell region selection. Only `mouseDown` is suppressed so the
/// system keeps rendering the cursor naturally. `handleMouseEvent`
/// runs on the CGEventTap thread (~1 ms budget); AX lookup is on
/// `lookupQueue`; overlay/window writes are main-actor.
@MainActor
final class GripDragCoordinator {

    static let shared = GripDragCoordinator()

    private nonisolated let stateLock = OSAllocatedUnfairLock<GripDragState>(initialState: .idle)
    private nonisolated let lookupQueue = DispatchQueue(
        label: "com.sniq.gripdrag.lookup", qos: .userInteractive
    )

    private let overlay = GripDragOverlayHost()
    private let flashIndicator = WindowFlashIndicator()

    private init() {}

    nonisolated func wire(to monitor: EventMonitor) {
        monitor.mouseHandler = { [weak self] event in
            guard let self else { return false }
            return self.handleMouseEvent(event)
        }
    }

    nonisolated func unwire(from monitor: EventMonitor) {
        monitor.mouseHandler = nil
        stateLock.withLock { $0 = .idle }
        Task { @MainActor [weak self] in self?.overlay.hide() }
    }

    /// Called synchronously from the CGEventTap callback. Returns `true`
    /// to claim (suppress) the event, `false` to pass it through.
    nonisolated func handleMouseEvent(_ event: RawMouseEvent) -> Bool {
        let current = stateLock.withLock { $0 }
        switch current {
        case .idle:
            return tryArm(on: event)
        case .armed(let downPos, let tracked, let variant):
            return advanceArmed(event: event, downPos: downPos, tracked: tracked, variant: variant)
        case .tracking(let tracked, let variant, let phase):
            return advanceTracking(event: event, tracked: tracked, variant: variant, phase: phase)
        }
    }

    private nonisolated func tryArm(on event: RawMouseEvent) -> Bool {
        guard event.kind == .mouseDown else { return false }
        guard !PauseState.isPaused else { return false }

        let bindings = ModifierBindings.load()
        let grip = bindings.grip
        guard !grip.isEmpty, grip.isSubset(of: event.modifiers) else { return false }
        // Reject non-role modifiers so Shift+Cmd+click etc. pass through.
        let known = grip.union(bindings.flip).union(bindings.stretch)
        guard event.modifiers.isSubset(of: known) else { return false }
        guard CursorWindowProbe.hasWindow(at: event.location) else { return false }

        let variant: LayoutVariant = bindings.flip.isSubset(of: event.modifiers) ? .secondary : .primary
        stateLock.withLock { $0 = .armed(downPos: event.location, tracked: nil, variant: variant) }
        dispatchAXLookup(at: event.location)
        return true
    }

    private nonisolated func advanceArmed(
        event: RawMouseEvent,
        downPos: CGPoint,
        tracked: TrackedWindow?,
        variant: LayoutVariant
    ) -> Bool {
        switch event.kind {
        case .mouseDown:
            return true  // defensive: swallow any second-button press during session

        case .mouseDragged:
            let dist = hypot(event.location.x - downPos.x, event.location.y - downPos.y)
            if dist >= 5, let tracked {
                let stretch = ModifierBindings.load().stretch
                let startPhase: TrackingPhase =
                    (!stretch.isEmpty && stretch.isSubset(of: event.modifiers))
                        ? .multi(anchor: GridCell(row: 0, col: 0))  // anchor refined in beginTracking
                        : .single
                stateLock.withLock { state in
                    if case .armed = state {
                        state = .tracking(tracked: tracked, variant: variant, phase: startPhase)
                    }
                }
                let point = event.location
                Task { @MainActor [weak self] in
                    self?.beginTracking(at: point, tracked: tracked, variant: variant)
                }
            }
            return false  // pass through so the cursor continues to render

        case .mouseUp:
            stateLock.withLock { $0 = .idle }
            return false

        case .flagsChanged:
            if !ModifierBindings.load().grip.isSubset(of: event.modifiers) {
                stateLock.withLock { $0 = .idle }
            }
            return false
        }
    }

    private nonisolated func advanceTracking(
        event: RawMouseEvent,
        tracked: TrackedWindow,
        variant: LayoutVariant,
        phase: TrackingPhase
    ) -> Bool {
        switch event.kind {
        case .mouseDown:
            return true  // defensive

        case .mouseDragged:
            let point = event.location
            Task { @MainActor [weak self] in self?.applyHighlight(at: point) }
            return false

        case .mouseUp:
            stateLock.withLock { $0 = .idle }
            let point = event.location
            Task { @MainActor [weak self] in
                self?.finishTracking(at: point, tracked: tracked, phase: phase)
            }
            return false

        case .flagsChanged:
            let bindings = ModifierBindings.load()
            if !bindings.grip.isSubset(of: event.modifiers) {
                stateLock.withLock { $0 = .idle }
                Task { @MainActor [weak self] in self?.cancelTracking() }
                return false
            }
            let flipIn = bindings.flip.isSubset(of: event.modifiers)
            let stretchIn = !bindings.stretch.isEmpty && bindings.stretch.isSubset(of: event.modifiers)
            let point = event.location
            Task { @MainActor [weak self] in
                self?.applyModifierChange(
                    at: point, tracked: tracked, flipHeld: flipIn, stretchHeld: stretchIn
                )
            }
            return false
        }
    }

    /// Resolves the AX window element on a background queue so the tap
    /// callback keeps its 1 ms budget. On success, promotes the armed
    /// state's `tracked` slot; on failure, unwinds state back to idle.
    private nonisolated func dispatchAXLookup(at point: CGPoint) {
        lookupQueue.async { [weak self] in
            guard let self else { return }
            guard let info = WindowDetector.shared.windowAtPoint(point),
                  !info.isFullscreen
            else {
                self.stateLock.withLock { state in
                    if case .armed = state { state = .idle }
                }
                return
            }
            let tracked = TrackedWindow(
                windowID: info.windowID,
                axElement: info.axElement,
                pid: info.pid,
                originalFrame: info.frame
            )
            self.stateLock.withLock { state in
                if case .armed(let downPos, _, let variant) = state {
                    state = .armed(downPos: downPos, tracked: tracked, variant: variant)
                }
            }
        }
    }

    private func beginTracking(at point: CGPoint, tracked: TrackedWindow, variant: LayoutVariant) {
        guard let screen = overlay.screenContaining(point: point) else { return }
        overlay.show(on: screen, variant: variant)
        flashIndicator.flash(cgFrame: tracked.originalFrame)
        // Refine the multi-cell anchor placeholder now that the resolver is built.
        if let cell = overlay.cell(at: point) {
            stateLock.withLock { state in
                if case .tracking(_, _, .multi) = state {
                    state = .tracking(tracked: tracked, variant: variant, phase: .multi(anchor: cell))
                }
            }
        }
        applyHighlight(at: point)
    }

    private func applyHighlight(at point: CGPoint) {
        let info = stateLock.withLock { state -> (LayoutVariant, TrackingPhase)? in
            if case .tracking(_, let v, let p) = state { return (v, p) }
            return nil
        }
        guard let (variant, phase) = info else { return }
        if let current = overlay.activeScreen,
           !current.visibleFrameCG.insetBy(dx: -1, dy: -1).contains(point),
           let newScreen = overlay.screenContaining(point: point),
           newScreen !== current {
            overlay.show(on: newScreen, variant: variant)
        }
        guard let cell = overlay.cell(at: point) else { return }
        switch phase {
        case .single:
            overlay.updateHighlight(cell: cell)
        case .multi(let anchor):
            overlay.updateHighlight(region: anchor, to: cell)
        }
    }

    /// Mid-drag: Flip (⌃) swaps layout in `.single` phase, Stretch (⌥)
    /// toggles `.single` ↔ `.multi`. Layout swap is skipped in `.multi`
    /// because the anchor cell loses meaning after a grid rebuild.
    private func applyModifierChange(
        at point: CGPoint,
        tracked: TrackedWindow,
        flipHeld: Bool,
        stretchHeld: Bool
    ) {
        let info = stateLock.withLock { state -> (LayoutVariant, TrackingPhase)? in
            if case .tracking(_, let v, let p) = state { return (v, p) }
            return nil
        }
        guard let (variant, phase) = info else { return }

        let targetVariant: LayoutVariant = flipHeld ? .secondary : .primary
        if case .single = phase, targetVariant != variant,
           let screen = overlay.activeScreen {
            overlay.show(on: screen, variant: targetVariant)
            stateLock.withLock {
                $0 = .tracking(tracked: tracked, variant: targetVariant, phase: .single)
            }
            if let cell = overlay.cell(at: point) { overlay.updateHighlight(cell: cell) }
            return
        }

        guard let cell = overlay.cell(at: point) else { return }
        switch (phase, stretchHeld) {
        case (.single, true):
            stateLock.withLock {
                $0 = .tracking(tracked: tracked, variant: variant, phase: .multi(anchor: cell))
            }
            overlay.updateHighlight(region: cell, to: cell)
        case (.multi, false):
            stateLock.withLock {
                $0 = .tracking(tracked: tracked, variant: variant, phase: .single)
            }
            overlay.updateHighlight(cell: cell)
        default:
            break
        }
    }

    private func finishTracking(at point: CGPoint, tracked: TrackedWindow, phase: TrackingPhase) {
        defer { overlay.hide() }
        guard let cell = overlay.cell(at: point) else { return }
        let targetRect: CGRect?
        let anchor: GridCell
        switch phase {
        case .single:
            targetRect = overlay.cellRect(at: cell)
            anchor = cell
        case .multi(let a):
            targetRect = overlay.regionUnion(from: a, to: cell)
            anchor = a
        }
        guard let rect = targetRect else { return }
        WindowManipulator.shared.setFrame(rect, for: tracked.axElement)
        recordInHistory(anchor: anchor, current: cell)
    }

    private func recordInHistory(anchor: GridCell, current: GridCell) {
        let (rows, cols) = overlay.gridDimensions
        guard rows > 0, cols > 0 else { return }
        let spec = SnapSpec(rows: rows, cols: cols, anchor: anchor, current: current)
        SnapHistory.shared.push(spec)
    }

    private func cancelTracking() {
        overlay.hide()
    }
}

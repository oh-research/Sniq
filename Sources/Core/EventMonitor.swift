@preconcurrency import Cocoa

// MARK: - Event data extracted in the CGEventTap callback

struct RawMouseEvent: Sendable {
    enum Kind: Sendable {
        case mouseDown
        case mouseDragged
        case mouseUp
        case flagsChanged
    }

    let kind: Kind
    let location: CGPoint
    let modifiers: PressedModifiers
}

// MARK: - EventMonitor

/// Installs a CGEventTap and routes events to two synchronous handlers:
/// `keyboardHandler` for keyDown events and `mouseHandler` for mouse
/// events. Each handler returns `true` to claim (suppress) the event or
/// `false` to pass it through. The tap callback itself extracts only
/// coordinates and flags so it stays well under the 1 ms budget.
final class EventMonitor: @unchecked Sendable {

    // MARK: State

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false

    /// Synchronous keyboard handler invoked from the CGEventTap callback
    /// thread. Return `true` to suppress the event (Sniq claims it); return
    /// `false` to pass it through to the system. Must return within the tap
    /// budget (~1 ms). Parameters: `(keyCode, pressedModifiers)`.
    var keyboardHandler: (@Sendable (Int64, PressedModifiers) -> Bool)?

    /// Synchronous mouse interceptor invoked from the CGEventTap callback
    /// thread. Return `true` to claim the event — the OS will not see it.
    /// Used by the Grip-drag coordinator to suppress mouse events while
    /// Grip is held. Must return within the tap budget (~1 ms).
    var mouseHandler: (@Sendable (RawMouseEvent) -> Bool)?

    /// Called on the main queue when the event tap cannot be created.
    var onTapCreationFailure: (@Sendable () -> Void)?

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        // Use active tap so keyboard shortcuts can suppress events when
        // claimed by Sniq. Passive (.listenOnly) cannot modify or block
        // events, which caused arrow escape sequences to leak into
        // terminal apps after window snapping.
        let newTap = createTap(options: .defaultTap, mask: eventMask)

        guard let newTap else {
            debugLog("[EventMonitor] FAILED to create CGEventTap")
            let cb = onTapCreationFailure
            DispatchQueue.main.async { cb?() }
            return
        }
        debugLog("[EventMonitor] CGEventTap created successfully")

        tap = newTap

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        isRunning = true
    }

    func stop() {
        guard isRunning, let tap else { return }

        CGEvent.tapEnable(tap: tap, enable: false)
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        runLoopSource = nil
        self.tap = nil
        isRunning = false
    }

    // MARK: - Private helpers

    private func createTap(options: CGEventTapOptions, mask: CGEventMask) -> CFMachPort? {
        // We need a raw pointer back to self for tap-disable recovery.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        return CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: mask,
            callback: EventMonitor.tapCallback,
            userInfo: selfPtr
        )
    }

    // MARK: - CGEventTap callback (must be a C function pointer)

    private static let tapCallback: CGEventTapCallBack = { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<EventMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        // --- Re-enable on timeout (must happen inside callback) ---
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // --- Extract only the minimum data needed (<1 ms budget) ---
        let location = event.location
        let flags = event.flags

        // --- Keyboard shortcut fast path: consult handler, suppress if claimed ---
        if type == .keyDown {
            guard let handler = monitor.keyboardHandler else {
                return Unmanaged.passUnretained(event)
            }
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let shouldSuppress = handler(keyCode, PressedModifiers(cgFlags: flags))
            return shouldSuppress ? nil : Unmanaged.passUnretained(event)
        }

        let kind: RawMouseEvent.Kind
        switch type {
        case .leftMouseDown:    kind = .mouseDown
        case .leftMouseDragged: kind = .mouseDragged
        case .leftMouseUp:      kind = .mouseUp
        case .flagsChanged:     kind = .flagsChanged
        default:
            return Unmanaged.passUnretained(event)
        }

        let raw = RawMouseEvent(
            kind: kind,
            location: location,
            modifiers: PressedModifiers(cgFlags: flags)
        )

        if let mouseHandler = monitor.mouseHandler, mouseHandler(raw) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}

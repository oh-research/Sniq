import os

/// Session-scoped pause switch. Deliberately not persisted — every
/// launch starts active, so a paused Sniq can never come back dead.
/// Read from the CGEventTap thread by both coordinators, hence the
/// lock instead of a main-actor property.
enum PauseState {
    private static let lock = OSAllocatedUnfairLock(initialState: false)

    static var isPaused: Bool {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}

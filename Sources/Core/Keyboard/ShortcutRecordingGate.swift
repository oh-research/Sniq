import Foundation
import os

/// Process-wide flag set by `KeyRecorder` while it is listening for a
/// shortcut. `CustomSnapCoordinator` reads it from the CGEventTap
/// thread and bails out of snap matching while the gate is on, so the
/// recorded key reaches AppKit's local event monitor instead of being
/// hijacked by a previously bound snap.
final class ShortcutRecordingGate: @unchecked Sendable {

    static let shared = ShortcutRecordingGate()

    private let flag = OSAllocatedUnfairLock<Bool>(initialState: false)

    private init() {}

    var isRecording: Bool { flag.withLock { $0 } }

    func beginRecording() { flag.withLock { $0 = true } }

    func endRecording() { flag.withLock { $0 = false } }
}

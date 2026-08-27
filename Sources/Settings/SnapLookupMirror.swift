import Foundation
import os

/// Nonisolated copy of the saved `Snap` list, read synchronously
/// from the CGEventTap callback thread. Written to by `SnapStore`
/// on every mutation. Separate from `SnapStore` because that type
/// is `@MainActor` for SwiftUI observation, which would prevent the
/// event-tap thread from calling in.
final class SnapLookupMirror: @unchecked Sendable {

    static let shared = SnapLookupMirror()

    private let lock = OSAllocatedUnfairLock<[Snap]>(initialState: [])

    private init() {}

    /// Replaces the mirrored list. Called from `SnapStore` after any
    /// persistence-visible change.
    func store(_ snaps: [Snap]) {
        lock.withLock { $0 = snaps }
    }

    /// First snap whose shortcut matches the key event, or `nil`.
    /// Template-only entries (`shortcut == nil`) are skipped so unbound
    /// drafts never hijack a key event. Safe to call from any thread.
    func lookup(keyCode: Int64, modifiers: PressedModifiers) -> Snap? {
        lock.withLock { list in
            list.first {
                guard let shortcut = $0.shortcut else { return false }
                return shortcut.keyCode == keyCode && shortcut.modifiers == modifiers
            }
        }
    }
}

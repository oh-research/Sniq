import Foundation
import Observation
import os

/// Persists user-saved `Snap`s in `UserDefaults` (JSON). The list
/// is observable by SwiftUI (main-actor). Fast `(keyCode, modifiers)`
/// matching from the CGEventTap thread happens via
/// `SnapLookupMirror.shared`, kept in sync by `persist()`.
@MainActor
@Observable
final class SnapStore {

    static let shared = SnapStore()

    private static let defaultsKey = "snapshots.v1"

    private(set) var snaps: [Snap] = []

    /// Most recently deleted snap plus the index it occupied. Held
    /// in memory for ~10 s so the Snaps window can offer an Undo
    /// snackbar. Cleared by a new deletion or by the expiration task.
    private(set) var lastDeletion: LastDeletion?

    private var expirationTask: Task<Void, Never>?

    private init() {
        load()
    }

    // MARK: - Mutation

    /// Adds `snap`, failing if another saved snap already uses the
    /// same (non-nil) shortcut. Multiple template-only entries (`shortcut
    /// == nil`) may coexist.
    @discardableResult
    func add(_ snap: Snap) -> Result<Void, MutationError> {
        if let shortcut = snap.shortcut {
            if let err = shortcut.validate() {
                return .failure(.invalidShortcut(err))
            }
            if let owner = snaps.first(where: { $0.shortcut == shortcut }) {
                return .failure(.shortcutTaken(owner: owner))
            }
        }
        snaps.append(snap)
        persist()
        return .success(())
    }

    /// Inserts a template-only snap using the user's primary grid as
    /// the default layout and a single top-left cell as the default region.
    /// The returned entry starts with `shortcut == nil` so the Saved row
    /// renders in the disabled state until the user assigns a shortcut.
    @discardableResult
    func addBlank() -> Snap {
        let prefs = PreferencesStore.shared
        let spec = SnapSpec(
            rows: max(1, prefs.primaryRows),
            cols: max(1, prefs.primaryCols),
            minCell: GridCell(row: 0, col: 0),
            maxCell: GridCell(row: 0, col: 0)
        )
        let snap = Snap(spec: spec, shortcut: nil)
        snaps.append(snap)
        persist()
        return snap
    }

    /// Replaces an existing snap's shortcut. Same collision rule as
    /// `add`. Pass `nil` to clear the shortcut (moves the row back to the
    /// disabled state).
    @discardableResult
    func updateShortcut(id: UUID, to shortcut: ShortcutSpec?) -> Result<Void, MutationError> {
        if let shortcut {
            if let err = shortcut.validate() {
                return .failure(.invalidShortcut(err))
            }
            if let owner = snaps.first(
                where: { $0.id != id && $0.shortcut == shortcut }
            ) {
                return .failure(.shortcutTaken(owner: owner))
            }
        }
        guard let idx = snaps.firstIndex(where: { $0.id == id }) else {
            return .failure(.notFound)
        }
        snaps[idx].shortcut = shortcut
        persist()
        return .success(())
    }

    /// Overwrite path: clears `ownerId`'s shortcut, then assigns the
    /// freed shortcut to `targetId`. Called after the user confirms an
    /// inline conflict warning.
    @discardableResult
    func reassignShortcut(
        from ownerId: UUID,
        to targetId: UUID,
        shortcut: ShortcutSpec
    ) -> Result<Void, MutationError> {
        _ = updateShortcut(id: ownerId, to: nil)
        return updateShortcut(id: targetId, to: shortcut)
    }

    /// Overwrite path for the Recent → Saved flow: clears `ownerId`'s
    /// shortcut, then inserts `snap` (which carries the freed shortcut).
    @discardableResult
    func reassignShortcut(
        from ownerId: UUID,
        adding snap: Snap
    ) -> Result<Void, MutationError> {
        _ = updateShortcut(id: ownerId, to: nil)
        return add(snap)
    }

    /// Replaces an existing snap's region/grid. No collision rule —
    /// multiple snaps may legitimately share the same geometry as
    /// long as their shortcuts differ.
    @discardableResult
    func updateSpec(id: UUID, to spec: SnapSpec) -> Result<Void, MutationError> {
        guard let idx = snaps.firstIndex(where: { $0.id == id }) else {
            return .failure(.notFound)
        }
        snaps[idx].spec = spec
        persist()
        return .success(())
    }

    func remove(id: UUID) {
        guard let idx = snaps.firstIndex(where: { $0.id == id }) else { return }
        let removed = snaps.remove(at: idx)
        lastDeletion = LastDeletion(snap: removed, index: idx)
        scheduleDeletionExpiry()
        persist()
    }

    /// Re-inserts the last-deleted snap at its original index. If the
    /// shortcut was claimed by another snap in the meantime the entry
    /// is restored as a template (shortcut = nil) so the lookup stays
    /// collision-free.
    @discardableResult
    func undoLastDeletion() -> Bool {
        guard let last = lastDeletion else { return false }
        lastDeletion = nil
        expirationTask?.cancel()
        expirationTask = nil

        var restored = last.snap
        if let shortcut = restored.shortcut,
           snaps.contains(where: { $0.shortcut == shortcut }) {
            restored.shortcut = nil
        }
        let idx = min(last.index, snaps.count)
        snaps.insert(restored, at: idx)
        persist()
        return true
    }

    private func scheduleDeletionExpiry() {
        expirationTask?.cancel()
        expirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled else { return }
            self.lastDeletion = nil
            self.expirationTask = nil
        }
    }

    struct LastDeletion: Equatable {
        let snap: Snap
        let index: Int
    }

    /// Bulk replace — used by the Import "Replace" flow.
    func replaceAll(_ newSnaps: [Snap]) {
        snaps = newSnaps
        persist()
    }

    /// Bulk append, skipping any whose (non-nil) shortcut already exists.
    /// Template-only entries (`shortcut == nil`) are always imported since
    /// they cannot collide. Returns counts for user feedback.
    @discardableResult
    func append(_ incoming: [Snap]) -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0
        for candidate in incoming {
            if let shortcut = candidate.shortcut,
               snaps.contains(where: { $0.shortcut == shortcut }) {
                skipped += 1
            } else {
                snaps.append(candidate)
                imported += 1
            }
        }
        if imported > 0 { persist() }
        return (imported, skipped)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else {
            return
        }
        do {
            snaps = try JSONDecoder().decode([Snap].self, from: data)
            SnapLookupMirror.shared.store(snaps)
        } catch {
            debugLog("[SnapStore] decode failed: \(error.localizedDescription)")
        }
    }

    private func persist() {
        SnapLookupMirror.shared.store(snaps)
        do {
            let data = try JSONEncoder().encode(snaps)
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        } catch {
            debugLog("[SnapStore] encode failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Errors

    enum MutationError: Error, Equatable {
        case shortcutTaken(owner: Snap)
        case notFound
        case invalidShortcut(ShortcutSpec.ValidationError)

        var message: String {
            switch self {
            case .shortcutTaken(let owner):
                return "Shortcut already used by \(owner.spec.summary)."
            case .notFound:
                return "Snap not found."
            case .invalidShortcut(let e):
                return e.message
            }
        }
    }
}


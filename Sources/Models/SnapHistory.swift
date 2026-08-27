import Observation

/// Session-only ring of the most recent `SnapSpec`s produced by Grip drags.
/// Capacity is fixed at 10; pushing an existing spec moves it to the top
/// rather than duplicating. The list is not persisted — sniq starts each
/// session with an empty history, matching its keep-it-decisive design.
@MainActor
@Observable
final class SnapHistory {

    static let shared = SnapHistory()
    static let capacity = 10

    private(set) var entries: [SnapSpec] = []

    private init() {}

    // MARK: - Mutation

    /// Inserts `spec` at position 0, removing any prior occurrence first so
    /// the same geometry never appears twice. Truncates to `capacity`.
    func push(_ spec: SnapSpec) {
        entries.removeAll { $0 == spec }
        entries.insert(spec, at: 0)
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
    }

    func clear() {
        entries.removeAll()
    }
}

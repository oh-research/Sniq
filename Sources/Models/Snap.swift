import Foundation

// MARK: - SnapSpec

/// The geometric half of a snap: which grid, which rectangular region.
/// Shared by `SnapHistory` entries (no shortcut yet) and saved `Snap`s
/// (with shortcut). `minCell == maxCell` means a single-cell snap.
struct SnapSpec: Codable, Equatable, Hashable, Sendable {
    var rows: Int
    var cols: Int
    var minCell: GridCell
    var maxCell: GridCell

    /// Normalizes so `minCell <= maxCell` component-wise. `GripDragCoordinator`
    /// already passes anchor/current in either order when the user drags up
    /// or left, so callers should funnel through this.
    init(rows: Int, cols: Int, anchor: GridCell, current: GridCell) {
        self.rows = rows
        self.cols = cols
        self.minCell = GridCell(
            row: min(anchor.row, current.row),
            col: min(anchor.col, current.col)
        )
        self.maxCell = GridCell(
            row: max(anchor.row, current.row),
            col: max(anchor.col, current.col)
        )
    }

    /// Raw initializer for decoded values.
    init(rows: Int, cols: Int, minCell: GridCell, maxCell: GridCell) {
        self.rows = rows
        self.cols = cols
        self.minCell = minCell
        self.maxCell = maxCell
    }

    /// Ordered ring of placements this snap cycles through on repeat
    /// presses. Starts at the snap's own region and steps toward the
    /// edge the region is anchored to — a left/top snap keeps moving
    /// left/up (wrapping to the far end), a right/bottom snap keeps
    /// moving right/down. Empty when the snap doesn't cycle: 2D grid,
    /// full-span region, or a middle region with no anchored edge.
    func stripCycle() -> [SnapSpec] {
        let length: Int
        let start: Int
        let size: Int
        if rows == 1, cols > 1 {
            (length, start, size) = (cols, minCell.col, maxCell.col - minCell.col + 1)
        } else if cols == 1, rows > 1 {
            (length, start, size) = (rows, minCell.row, maxCell.row - minCell.row + 1)
        } else {
            return []
        }

        let lastStart = length - size
        let step: Int
        if lastStart > 0, start == 0 {
            step = -1
        } else if lastStart > 0, start == lastStart {
            step = 1
        } else {
            return []
        }

        let count = lastStart + 1
        return (0 ..< count).map { offset in
            placedAlongStrip(at: ((start + offset * step) % count + count) % count, size: size)
        }
    }

    private func placedAlongStrip(at start: Int, size: Int) -> SnapSpec {
        if rows == 1 {
            return SnapSpec(
                rows: rows, cols: cols,
                minCell: GridCell(row: 0, col: start),
                maxCell: GridCell(row: 0, col: start + size - 1)
            )
        }
        return SnapSpec(
            rows: rows, cols: cols,
            minCell: GridCell(row: start, col: 0),
            maxCell: GridCell(row: start + size - 1, col: 0)
        )
    }

    /// Human-readable summary for UI: `"3×2 · (0,0)→(0,1)"` or `"2×2 · (1,1)"`.
    var summary: String {
        let grid = "\(rows)×\(cols)"
        if minCell == maxCell {
            return "\(grid) · (\(minCell.row),\(minCell.col))"
        }
        return "\(grid) · (\(minCell.row),\(minCell.col))→(\(maxCell.row),\(maxCell.col))"
    }
}

// MARK: - Snap

/// A saved snap: geometry + an optional keyboard shortcut. A `nil`
/// shortcut marks the entry as a template-only draft — it persists and
/// shows in the Saved list but is skipped by the hotkey dispatcher until
/// the user assigns one.
struct Snap: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var spec: SnapSpec
    var shortcut: ShortcutSpec?

    init(id: UUID = UUID(), spec: SnapSpec, shortcut: ShortcutSpec?) {
        self.id = id
        self.spec = spec
        self.shortcut = shortcut
    }
}

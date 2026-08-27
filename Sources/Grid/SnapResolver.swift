// SnapResolver.swift
// Pure logic — no UI dependencies. All coordinates are in CG coordinate system (top-left origin).
import CoreGraphics

struct SnapResolver {
    let cells: [[CGRect]]

    private var rows: Int { cells.count }
    private var cols: Int { cells.first?.count ?? 0 }

    /// The origin of the grid (top-left corner of cell[0][0]).
    private var gridOrigin: CGPoint {
        cells[0][0].origin
    }

    /// Effective cell width including the gap (used for O(1) column lookup).
    /// For the last column there is no trailing gap, but the formula still clamps correctly.
    private var effectiveCellW: CGFloat {
        guard cols > 0 else { return 0 }
        // gap between columns = cells[0][1].minX - cells[0][0].maxX
        if cols == 1 { return cells[0][0].width }
        return cells[0][1].minX - cells[0][0].minX
    }

    /// Effective cell height including the gap (used for O(1) row lookup).
    private var effectiveCellH: CGFloat {
        guard rows > 0 else { return 0 }
        if rows == 1 { return cells[0][0].height }
        return cells[1][0].minY - cells[0][0].minY
    }

    // MARK: - Single cell

    /// Resolves the grid cell that the cursor falls in. Clamps to valid range when cursor is
    /// outside the grid bounds.
    /// - Parameter cursor: Cursor position in CG coordinates.
    /// - Returns: The nearest `GridCell`, or `nil` when the cells array is empty.
    func cell(at cursor: CGPoint) -> GridCell? {
        guard rows > 0, cols > 0 else { return nil }

        let origin = gridOrigin
        let ew = effectiveCellW
        let eh = effectiveCellH

        let rawCol = ew > 0 ? Int(floor((cursor.x - origin.x) / ew)) : 0
        let rawRow = eh > 0 ? Int(floor((cursor.y - origin.y) / eh)) : 0

        let col = min(max(rawCol, 0), cols - 1)
        let row = min(max(rawRow, 0), rows - 1)

        return GridCell(row: row, col: col)
    }
}

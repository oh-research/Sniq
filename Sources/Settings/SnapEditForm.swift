import SwiftUI

/// Expanded-state editor for a single saved snap. Mutates `rows`,
/// `cols`, `minCell`, and `maxCell` through bindings; the parent (a
/// saved row) persists the new spec on every change. Stepper ranges
/// clamp so `minCell <= maxCell` and both stay inside the grid.
struct SnapEditForm: View {

    @Binding var rows: Int
    @Binding var cols: Int
    @Binding var minRow: Int
    @Binding var minCol: Int
    @Binding var maxRow: Int
    @Binding var maxCol: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                stepper("Rows",    value: $rows, range: 1...10, onChange: clampCells)
                stepper("Columns", value: $cols, range: 1...10, onChange: clampCells)
            }
            HStack(spacing: 16) {
                coordPair(label: "From", row: $minRow, col: $minCol) { clampMax() }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                coordPair(label: "To",   row: $maxRow, col: $maxCol) { clampMin() }
            }
        }
    }

    // MARK: - Primitives

    private func stepper(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        onChange: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
            Text("\(value.wrappedValue)")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 20, alignment: .trailing)
            Stepper("", value: value, in: range)
                .labelsHidden()
                .controlSize(.small)
                .onChange(of: value.wrappedValue) { _, _ in onChange() }
        }
    }

    private func coordPair(
        label: String,
        row: Binding<Int>,
        col: Binding<Int>,
        onChange: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            coordStepper(value: row, max: rows - 1, onChange: onChange)
            Text(",")
                .font(.caption)
                .foregroundStyle(.tertiary)
            coordStepper(value: col, max: cols - 1, onChange: onChange)
        }
    }

    private func coordStepper(
        value: Binding<Int>,
        max: Int,
        onChange: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 2) {
            Text("\(value.wrappedValue)")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 14, alignment: .trailing)
            Stepper("", value: value, in: 0...Swift.max(0, max))
                .labelsHidden()
                .controlSize(.small)
                .onChange(of: value.wrappedValue) { _, _ in onChange() }
        }
    }

    // MARK: - Clamping

    /// Pulls cell indexes back inside the grid whenever rows/cols shrink.
    private func clampCells() {
        if minRow > rows - 1 { minRow = rows - 1 }
        if maxRow > rows - 1 { maxRow = rows - 1 }
        if minCol > cols - 1 { minCol = cols - 1 }
        if maxCol > cols - 1 { maxCol = cols - 1 }
        if minRow > maxRow { maxRow = minRow }
        if minCol > maxCol { maxCol = minCol }
    }

    private func clampMin() {
        if maxRow < minRow { minRow = maxRow }
        if maxCol < minCol { minCol = maxCol }
    }

    private func clampMax() {
        if minRow > maxRow { maxRow = minRow }
        if minCol > maxCol { maxCol = minCol }
    }
}

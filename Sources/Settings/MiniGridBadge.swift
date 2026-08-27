import SwiftUI

/// Tiny 28×18 grid glyph that highlights the snap's region, giving
/// the user an at-a-glance shape without parsing the numeric summary.
struct MiniGridBadge: View {
    let spec: SnapSpec

    var body: some View {
        Canvas { context, size in
            let cellW = size.width  / CGFloat(spec.cols)
            let cellH = size.height / CGFloat(spec.rows)

            let hx = CGFloat(spec.minCell.col) * cellW
            let hy = CGFloat(spec.minCell.row) * cellH
            let hw = CGFloat(spec.maxCell.col - spec.minCell.col + 1) * cellW
            let hh = CGFloat(spec.maxCell.row - spec.minCell.row + 1) * cellH
            context.fill(
                Path(CGRect(x: hx, y: hy, width: hw, height: hh).insetBy(dx: 1, dy: 1)),
                with: .color(.accentColor.opacity(0.55))
            )

            for c in 0...spec.cols {
                var path = Path()
                path.move(to: CGPoint(x: CGFloat(c) * cellW, y: 0))
                path.addLine(to: CGPoint(x: CGFloat(c) * cellW, y: size.height))
                context.stroke(path, with: .color(.secondary.opacity(0.45)), lineWidth: 0.5)
            }
            for r in 0...spec.rows {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: CGFloat(r) * cellH))
                path.addLine(to: CGPoint(x: size.width, y: CGFloat(r) * cellH))
                context.stroke(path, with: .color(.secondary.opacity(0.45)), lineWidth: 0.5)
            }
        }
        .frame(width: 28, height: 18)
    }
}

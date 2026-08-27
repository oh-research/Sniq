import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var launchAtLogin = LoginItemHelper.isEnabled

    var body: some View {
        VStack(spacing: 14) {
            LayoutEditor(
                title: "Primary layout",
                modifierBadge: prefs.bindings.grip.formatted,
                accent: .accentColor,
                rows: $prefs.primaryRows,
                cols: $prefs.primaryCols
            )

            LayoutEditor(
                title: "Secondary layout",
                modifierBadge: "\(prefs.bindings.grip.formatted) + \(prefs.bindings.flip.formatted)",
                accent: .secondary,
                rows: $prefs.secondaryRows,
                cols: $prefs.secondaryCols
            )

            GroupBox(label:
                Label("Modifier bindings", systemImage: "command")
                    .labelStyle(.titleAndIcon)
            ) {
                ModifierBindingView()
            }

            HStack {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        LoginItemHelper.setEnabled(launchAtLogin)
                    }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        // Suppresses the blue focus ring that macOS auto-attaches to the
        // first focusable control (Rows stepper) when the window opens.
        .focusEffectDisabled()
    }
}

// MARK: - Per-layout editor

private struct LayoutEditor: View {
    let title: String
    let modifierBadge: String
    let accent: Color
    @Binding var rows: Int
    @Binding var cols: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 6) {
                    dimensionRow(label: "Rows",    value: $rows)
                    dimensionRow(label: "Columns", value: $cols)
                }
                .frame(width: 150)

                LayoutGridPreview(rows: rows, cols: cols, accent: accent)
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 90)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.split.3x3.fill")
                .foregroundStyle(accent)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(modifierBadge)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.12))
                )
            Spacer()
        }
    }

    private func dimensionRow(label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
            Text("\(value.wrappedValue)")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 22, alignment: .trailing)
            Stepper("", value: value, in: 1...10)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

// MARK: - Grid preview

/// Draws each cell as a small rounded rectangle filled with the layout's
/// accent color — gives the settings pane a screen-like feel instead of
/// a flat wireframe. Respects a 16:10 aspect ratio from the parent.
struct LayoutGridPreview: View {
    let rows: Int
    let cols: Int
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 3
            let cellW = (size.width  - CGFloat(cols - 1) * gap) / CGFloat(cols)
            let cellH = (size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)

            for r in 0..<rows {
                for c in 0..<cols {
                    let x = CGFloat(c) * (cellW + gap)
                    let y = CGFloat(r) * (cellH + gap)
                    let rect = CGRect(x: x, y: y, width: cellW, height: cellH)
                    let path = Path(roundedRect: rect, cornerRadius: 4)
                    context.fill(path, with: .color(accent.opacity(0.18)))
                    context.stroke(path, with: .color(accent.opacity(0.55)), lineWidth: 1)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }
}

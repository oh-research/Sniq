import SwiftUI

/// Inline warning shown below a row when a shortcut the user just
/// recorded is already bound to another snap. Offers a two-button
/// resolution — overwrite the other binding, or cancel. Keeps conflict
/// UX local to the row instead of a window-level error string.
struct ConflictBanner: View {
    let shortcut: ShortcutSpec
    let owner: Snap
    let onOverwrite: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Already used by")
                        .font(.caption)
                    KeycapView(spec: shortcut, isDimmed: true)
                }
                Text(owner.spec.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // `.borderedProminent + .tint` desaturates when the window
            // is inactive, so the Overwrite button vanishes against the
            // pale orange banner. Drawing the fill directly keeps the
            // CTA readable regardless of window focus.
            Button(action: onOverwrite) {
                Text("Overwrite")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)

            Button("Cancel", action: onCancel)
                .controlSize(.small)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.35), lineWidth: 0.5)
        )
    }
}

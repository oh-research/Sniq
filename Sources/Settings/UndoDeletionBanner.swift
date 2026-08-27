import SwiftUI

/// Snackbar shown at the bottom of the Snaps window for ~10 s after
/// the user deletes a snap. Offers an inline Undo that re-inserts
/// the entry at its original index. After the window closes the
/// deleted snap is gone for good.
struct UndoDeletionBanner: View {
    let deletion: SnapStore.LastDeletion
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text("Deleted · \(deletion.snap.spec.summary)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
    }
}

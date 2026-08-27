import SwiftUI

/// Row in the Recent list. If no saved snap already owns this spec,
/// shows a `KeyRecorder` inline so the user can promote the recent snap
/// to Saved in one gesture. Handles the same overwrite-or-cancel inline
/// conflict resolution as `SavedRow`.
struct RecentRow: View {
    let spec: SnapSpec
    let onError: (String) -> Void

    @State private var draft: ShortcutSpec?
    @State private var hovering = false
    @State private var pendingConflict: Conflict?

    private struct Conflict: Equatable {
        let shortcut: ShortcutSpec
        let owner: Snap
    }

    private var savedShortcut: ShortcutSpec? {
        SnapStore.shared.snaps
            .first { $0.spec == spec && $0.shortcut != nil }?.shortcut
    }

    var body: some View {
        VStack(spacing: 6) {
            mainRow
            if let conflict = pendingConflict {
                ConflictBanner(
                    shortcut: conflict.shortcut,
                    owner: conflict.owner,
                    onOverwrite: { resolveConflict(conflict, overwrite: true) },
                    onCancel:    { resolveConflict(conflict, overwrite: false) }
                )
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
        )
        .onHover { hovering = $0 }
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            MiniGridBadge(spec: spec)
            Text(spec.summary)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            if let savedShortcut {
                HStack(spacing: 6) {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    KeycapView(spec: savedShortcut, isDimmed: true)
                }
            } else {
                KeyRecorder(spec: $draft, placeholder: "Assign shortcut…")
                    .onChange(of: draft) { _, new in
                        guard let new else { return }
                        handleNewShortcut(new)
                    }
            }
        }
    }

    // MARK: - Shortcut mutation

    private func handleNewShortcut(_ new: ShortcutSpec) {
        // A fresh recording supersedes any unresolved conflict — the user
        // is answering the prompt by picking a different key.
        pendingConflict = nil
        let snap = Snap(spec: spec, shortcut: new)
        let result = SnapStore.shared.add(snap)
        switch result {
        case .success:
            break
        case .failure(.shortcutTaken(let owner)):
            pendingConflict = Conflict(shortcut: new, owner: owner)
        case .failure(let err):
            onError(err.message)
            draft = nil
        }
    }

    private func resolveConflict(_ conflict: Conflict, overwrite: Bool) {
        if overwrite {
            let snap = Snap(spec: spec, shortcut: conflict.shortcut)
            SnapStore.shared.reassignShortcut(from: conflict.owner.id, adding: snap)
        }
        pendingConflict = nil
        draft = nil
    }
}

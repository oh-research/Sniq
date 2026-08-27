import SwiftUI

/// Row in the Saved list. Shows spec + shortcut, supports expanding the
/// grid/region editor, and handles inline shortcut conflict resolution
/// via `ConflictBanner` — the user can overwrite the other binding or
/// cancel without leaving the row.
struct SavedRow: View {
    let snap: Snap
    let onError: (String) -> Void

    @State private var hovering = false
    @State private var expanded = false
    @State private var editingShortcut = false
    @State private var draft: ShortcutSpec?
    @State private var pendingConflict: Conflict?

    private struct Conflict: Equatable {
        let shortcut: ShortcutSpec
        let owner: Snap
    }

    var body: some View {
        VStack(spacing: 6) {
            header
            if expanded { editor }
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
                .fill(hovering || expanded
                      ? Color.accentColor.opacity(0.08)
                      : Color.secondary.opacity(0.05))
        )
        .opacity(snap.shortcut == nil ? 0.55 : 1)
        .onHover { hovering = $0 }
    }

    // MARK: - Collapsed header

    private var header: some View {
        HStack(spacing: 10) {
            // Clicking anywhere on the spec side (chevron, badge, summary)
            // toggles the editor. Only the shortcut control and trash stay
            // as their own hit targets.
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    MiniGridBadge(spec: snap.spec)
                    Text(snap.spec.summary)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            shortcutControl
            Button {
                SnapStore.shared.remove(id: snap.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(hovering ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove snap")
        }
    }

    @ViewBuilder
    private var shortcutControl: some View {
        if editingShortcut || snap.shortcut == nil {
            KeyRecorder(
                spec: $draft,
                placeholder: "Assign shortcut…",
                autoStart: editingShortcut,
                onCancel: { editingShortcut = false },
                onClear:  { clearShortcut() }
            )
            .onChange(of: draft) { _, new in
                guard let new else { return }
                handleNewShortcut(new)
            }
        } else if let shortcut = snap.shortcut {
            Button {
                draft = shortcut
                editingShortcut = true
            } label: {
                KeycapView(spec: shortcut)
            }
            .buttonStyle(.plain)
            .help("Click to change shortcut")
        }
    }

    // MARK: - Shortcut mutation

    private func handleNewShortcut(_ new: ShortcutSpec) {
        // A fresh recording supersedes any unresolved conflict — the user
        // is answering the prompt by picking a different key.
        pendingConflict = nil
        let result = SnapStore.shared.updateShortcut(id: snap.id, to: new)
        switch result {
        case .success:
            editingShortcut = false
        case .failure(.shortcutTaken(let owner)):
            pendingConflict = Conflict(shortcut: new, owner: owner)
        case .failure(let err):
            onError(err.message)
            draft = nil
            editingShortcut = false
        }
    }

    private func resolveConflict(_ conflict: Conflict, overwrite: Bool) {
        if overwrite {
            SnapStore.shared.reassignShortcut(
                from: conflict.owner.id,
                to: snap.id,
                shortcut: conflict.shortcut
            )
        }
        pendingConflict = nil
        draft = nil
        editingShortcut = false
    }

    /// Invoked when the user presses Delete while the recorder is
    /// listening — unbinds the shortcut and moves the row back to the
    /// disabled template state.
    private func clearShortcut() {
        pendingConflict = nil
        SnapStore.shared.updateShortcut(id: snap.id, to: nil)
        draft = nil
        editingShortcut = false
    }

    // MARK: - Expanded editor

    private var editor: some View {
        SnapEditForm(
            rows:   specBinding(\.rows),
            cols:   specBinding(\.cols),
            minRow: Binding(
                get: { snap.spec.minCell.row },
                set: { setCell(\.minCell, row: $0) }
            ),
            minCol: Binding(
                get: { snap.spec.minCell.col },
                set: { setCell(\.minCell, col: $0) }
            ),
            maxRow: Binding(
                get: { snap.spec.maxCell.row },
                set: { setCell(\.maxCell, row: $0) }
            ),
            maxCol: Binding(
                get: { snap.spec.maxCell.col },
                set: { setCell(\.maxCell, col: $0) }
            )
        )
        .padding(.top, 8)
        .padding(.leading, 28)
        .padding(.bottom, 4)
    }

    // MARK: - Bindings bridging to the store

    private func specBinding(_ keyPath: WritableKeyPath<SnapSpec, Int>) -> Binding<Int> {
        Binding(
            get: { snap.spec[keyPath: keyPath] },
            set: { new in
                var updated = snap.spec
                updated[keyPath: keyPath] = new
                SnapStore.shared.updateSpec(id: snap.id, to: updated)
            }
        )
    }

    private func setCell(
        _ which: WritableKeyPath<SnapSpec, GridCell>,
        row: Int? = nil,
        col: Int? = nil
    ) {
        var updated = snap.spec
        let current = updated[keyPath: which]
        updated[keyPath: which] = GridCell(
            row: row ?? current.row,
            col: col ?? current.col
        )
        SnapStore.shared.updateSpec(id: snap.id, to: updated)
    }
}

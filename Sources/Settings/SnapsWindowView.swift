import SwiftUI
import UniformTypeIdentifiers

/// Dedicated window for managing snaps. Holds Recent + Saved lists
/// inside scrollable regions so the window stays short even when many
/// snaps accumulate, plus Export/Import buttons at the bottom. Drops
/// a `.sniq` file anywhere on the window to import.
struct SnapsWindowView: View {

    @ObservedObject private var preferences = PreferencesStore.shared

    private let history = SnapHistory.shared
    private let store   = SnapStore.shared

    @State private var pendingError: String?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            savedSection
            recentSection
            exportImportRow
            if let pendingError {
                Text(pendingError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let deletion = store.lastDeletion {
                UndoDeletionBanner(deletion: deletion) {
                    store.undoLastDeletion()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.lastDeletion)
        .padding(20)
        .frame(minWidth: 460, minHeight: 520)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay(dropIndicator)
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first,
              provider.canLoadObject(ofClass: URL.self)
        else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                SnapIO.importFile(at: url)
            }
        }
        return true
    }

    private var dropIndicator: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(
                Color.accentColor,
                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
            )
            .padding(6)
            .opacity(isDropTargeted ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
            .allowsHitTesting(false)
    }

    // MARK: - Saved

    private var savedSection: some View {
        GroupBox(label: savedHeader) {
            if store.snaps.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    EmptyStateRow(
                        systemImage: "square.dashed",
                        text: "Click + to add a snap, or assign a shortcut to a recent snap."
                    )
                    Button {
                        SnapIO.loadDefaults()
                    } label: {
                        Label("Load default shortcuts", systemImage: "sparkles")
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
                    .help("Adds the Rectangle-style starter set: ⌃⌥ arrows for halves, U/I/J/K for quarters, Return to maximize")
                }
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.snaps) { snap in
                            SavedRow(snap: snap, onError: { pendingError = $0 })
                        }
                    }
                    .padding(.vertical, 2)
                    // Reserve room for macOS' overlay scroll bar so the
                    // row's trash / shortcut controls stay reachable when
                    // the list overflows.
                    .padding(.trailing, 14)
                }
                // 15 compact rows × ~30pt + spacing. Taller lists scroll
                // inside this window; expanded rows grow the list too.
                .frame(maxHeight: 510)
            }
        }
    }

    private var savedHeader: some View {
        HStack(spacing: 6) {
            Label("Saved · \(store.snaps.count)", systemImage: "bookmark.fill")
                .labelStyle(.titleAndIcon)
            Spacer()
            Button {
                _ = store.addBlank()
            } label: {
                Image(systemName: "plus")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Add an empty snap — assign a shortcut to activate it")
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        GroupBox(label:
            Label("Recent · \(history.entries.count)", systemImage: "clock.arrow.circlepath")
                .labelStyle(.titleAndIcon)
        ) {
            if history.entries.isEmpty {
                EmptyStateRow(
                    systemImage: "hand.draw",
                    text: "Hold \(preferences.bindings.grip.formatted) and drag a window to create your first snap."
                )
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(history.entries, id: \.self) { spec in
                            RecentRow(spec: spec, onError: { pendingError = $0 })
                        }
                    }
                    .padding(.vertical, 2)
                    // Reserve room for macOS' overlay scroll bar so the
                    // row's trash / shortcut controls stay reachable when
                    // the list overflows.
                    .padding(.trailing, 14)
                }
                .frame(maxHeight: 220)
            }
        }
    }

    // MARK: - Export / Import

    private var exportImportRow: some View {
        HStack(spacing: 8) {
            Button {
                SnapIO.export()
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            Button {
                SnapIO.importFromUser()
            } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
            Spacer()
        }
    }
}

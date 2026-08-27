import Cocoa

/// Import/export glue between `SnapStore` and user-picked `.sniq`
/// files. Presents `NSSavePanel` / `NSOpenPanel` with a remembered last
/// directory (default `~/Documents/Sniq/`) and, on import, prompts the
/// user to choose Append vs Replace.
@MainActor
enum SnapIO {

    private static let lastDirectoryKey = "snapIO.lastDirectory"

    // MARK: - Export

    static func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "snaps-\(dateStamp()).sniq"
        panel.directoryURL = initialDirectory()
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        rememberDirectory(url.deletingLastPathComponent())

        let text = SnapFile.serialize(SnapStore.shared.snaps)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showAlert(title: "Export failed", message: error.localizedDescription)
        }
    }

    // MARK: - Import

    static func importFromUser() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = initialDirectory()

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile(at: url)
    }

    /// Shared entry for "the user gave us this `.sniq` file" — used by
    /// both the Import… panel and the drag-and-drop handler on the
    /// Snaps window.
    static func importFile(at url: URL) {
        guard url.pathExtension.lowercased() == "sniq" else {
            showAlert(
                title: "Unsupported file",
                message: "Only .sniq files can be imported."
            )
            return
        }
        rememberDirectory(url.deletingLastPathComponent())

        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            showAlert(title: "Import failed", message: error.localizedDescription)
            return
        }
        let result = SnapFile.parse(text)
        promptApply(result: result, filename: url.lastPathComponent)
    }

    // MARK: - Apply prompt

    private static func promptApply(result: SnapFile.ParseResult, filename: String) {
        if result.snaps.isEmpty {
            let detail = result.issues.isEmpty
                ? "No snaps were found in \(filename)."
                : issueSummary(result.issues)
            showAlert(title: "Nothing to import", message: detail)
            return
        }

        // Nothing saved yet — Append and Replace are identical, so the
        // choice would be noise. Import directly.
        if SnapStore.shared.snaps.isEmpty {
            let stats = SnapStore.shared.append(result.snaps)
            reportOutcome(imported: stats.imported, skipped: stats.skipped, issues: result.issues)
            return
        }

        let saved = savedPhrase(SnapStore.shared.snaps.count)
        let preview = previewAppend(result.snaps)
        let appendLine = preview.skipped == 0
            ? "Append: keep your \(saved) and add all \(result.snaps.count)."
            : "Append: keep your \(saved) and add \(preview.addable) — "
                + "\(preview.skipped) skipped (shortcut already in use)."
        let replaceLine = "Replace: delete your \(saved) and import all \(result.snaps.count)."

        let alert = NSAlert()
        alert.messageText = "Import \(result.snaps.count) snaps from \(filename)?"
        alert.informativeText = appendLine + "\n" + replaceLine
        alert.addButton(withTitle: "Append")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let stats = SnapStore.shared.append(result.snaps)
            reportOutcome(imported: stats.imported, skipped: stats.skipped, issues: result.issues)
        case .alertSecondButtonReturn:
            SnapStore.shared.replaceAll(result.snaps)
            reportOutcome(
                imported: result.snaps.count,
                skipped: 0,
                issues: result.issues
            )
        default:
            return
        }
    }

    /// Dry-runs `SnapStore.append`'s collision rule so the dialog can show
    /// exact counts: non-nil shortcuts already in use (or duplicated earlier
    /// in the same file) are skipped, everything else is addable.
    private static func previewAppend(_ incoming: [Snap]) -> (addable: Int, skipped: Int) {
        var taken = SnapStore.shared.snaps.compactMap(\.shortcut)
        var addable = 0
        var skipped = 0
        for candidate in incoming {
            if let shortcut = candidate.shortcut, taken.contains(shortcut) {
                skipped += 1
            } else {
                if let shortcut = candidate.shortcut { taken.append(shortcut) }
                addable += 1
            }
        }
        return (addable, skipped)
    }

    private static func savedPhrase(_ count: Int) -> String {
        count == 1 ? "1 saved snap" : "\(count) saved snaps"
    }

    private static func reportOutcome(
        imported: Int, skipped: Int, issues: [SnapFile.Issue]
    ) {
        var lines: [String] = []
        lines.append("\(imported) imported" + (skipped > 0 ? ", \(skipped) skipped" : ""))
        if !issues.isEmpty { lines.append(issueSummary(issues)) }
        showAlert(title: "Import complete", message: lines.joined(separator: "\n\n"))
    }

    private static func issueSummary(_ issues: [SnapFile.Issue]) -> String {
        let head = issues.prefix(5).map { "• line \($0.line): \($0.message)" }.joined(separator: "\n")
        if issues.count <= 5 { return head }
        return head + "\n• … and \(issues.count - 5) more"
    }

    // MARK: - Directory memory

    private static func initialDirectory() -> URL {
        if let path = UserDefaults.standard.string(forKey: lastDirectoryKey),
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return defaultDirectory()
    }

    private static func rememberDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: lastDirectoryKey)
    }

    private static func defaultDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return docs.appendingPathComponent("Sniq", isDirectory: true)
    }

    // MARK: - Misc

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

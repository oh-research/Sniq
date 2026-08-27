import Foundation

// MARK: - SnapFile

/// Reads and writes sniq's human-editable `.sniq` format — a forgiving
/// INI variant with `[snap]` sections and `key = value` lines.
/// Keeps errors line-numbered so the Import UI can point at exactly
/// what went wrong.
enum SnapFile {

    // MARK: - Serialization

    /// Produces the full `.sniq` file contents for `snaps`, prefixed
    /// by a header comment documenting the format.
    static func serialize(_ snaps: [Snap]) -> String {
        var output = header
        for snap in snaps {
            output += "\n"
            output += section(for: snap)
        }
        return output
    }

    private static func section(for snap: Snap) -> String {
        let spec = snap.spec
        var lines = ["[snap]"]
        lines.append("grid     = \(spec.rows)x\(spec.cols)")
        if spec.minCell == spec.maxCell {
            lines.append("region   = \(spec.minCell.row),\(spec.minCell.col)")
        } else {
            lines.append(
                "region   = \(spec.minCell.row),\(spec.minCell.col) -> " +
                "\(spec.maxCell.row),\(spec.maxCell.col)"
            )
        }
        if let shortcut = snap.shortcut {
            lines.append("shortcut = \(shortcut.sniqString)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Parsing

    /// Parses the `.sniq` text into a list of snaps plus a list of
    /// per-block errors that callers can show to the user. Bad blocks
    /// are skipped so a single typo doesn't kill the whole import.
    static func parse(_ text: String) -> ParseResult {
        var parser = SniqParser(text: text)
        return parser.run()
    }

    struct ParseResult {
        var snaps: [Snap]
        var issues: [Issue]
    }

    struct Issue: Equatable {
        let line: Int
        let message: String
    }

    // MARK: - Header (written by `serialize`, ignored by parser)

    private static let header = """
        # Sniq Snaps — version 1
        #
        # Format
        #   [snap]
        #   grid     = <rows>x<cols>                e.g. 3x2
        #   region   = <r>,<c>  or  <r>,<c> -> <r>,<c>   (0-based cell index)
        #   shortcut = <mod>+...+<key>              case-insensitive, `+` or space
        #
        # Modifiers:     cmd, ctrl, opt (= alt), shift
        # Letter keys:   a..z
        # Digit keys:    0..9
        # Arrow keys:    left, right, up, down
        # Function keys: f1..f12
        # Special keys:  space, tab, return, esc, delete,
        #                pageup, pagedown, home, end
        #
        # Lines starting with "#" are comments. Blank lines are ignored.
        """
}

// MARK: - Parser

/// One-pass line-oriented parser. Keeps only the current block in state
/// so parse errors always reference the originating line number. Missing
/// fields inside a block are reported when the block closes.
private struct SniqParser {

    let text: String

    private var snaps: [Snap] = []
    private var issues: [SnapFile.Issue] = []

    private var current: Block?

    init(text: String) {
        self.text = text
    }

    mutating func run() -> SnapFile.ParseResult {
        for (index, rawLine) in text.split(
            separator: "\n", omittingEmptySubsequences: false
        ).enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                commitCurrent()
                let name = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
                // `[snapshot]` is the legacy section name from sniq ≤ 1.3.
                // Accepted silently so older export files still import.
                if name == "snap" || name == "snapshot" {
                    current = Block(startLine: lineNumber)
                } else {
                    issues.append(.init(line: lineNumber, message: "unknown section \"[\(name)]\""))
                    current = nil
                }
                continue
            }

            guard let eq = line.firstIndex(of: "=") else {
                issues.append(.init(line: lineNumber, message: "expected `key = value`"))
                continue
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            guard current != nil else {
                issues.append(.init(
                    line: lineNumber,
                    message: "\(key) outside of a [snap] block"
                ))
                continue
            }

            switch key {
            case "grid":     apply(grid: value, line: lineNumber)
            case "region":   apply(region: value, line: lineNumber)
            case "shortcut": apply(shortcut: value, line: lineNumber)
            default:
                issues.append(.init(
                    line: lineNumber,
                    message: "unknown key \"\(key)\""
                ))
            }
        }
        commitCurrent()
        return .init(snaps: snaps, issues: issues)
    }

    // MARK: - Field application

    private mutating func apply(grid value: String, line: Int) {
        let parts = value.lowercased().split(separator: "x")
        guard parts.count == 2,
              let rows = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let cols = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              rows >= 1, cols >= 1
        else {
            issues.append(.init(
                line: line,
                message: "grid \"\(value)\" malformed — expected \"<rows>x<cols>\""
            ))
            return
        }
        current?.rows = rows
        current?.cols = cols
    }

    private mutating func apply(region value: String, line: Int) {
        let sides = value.components(separatedBy: "->")
        guard sides.count == 1 || sides.count == 2 else {
            issues.append(.init(line: line, message: "region has too many \"->\""))
            return
        }
        guard let minCell = parseCell(sides[0].trimmingCharacters(in: .whitespaces)) else {
            issues.append(.init(line: line, message: "region min cell malformed"))
            return
        }
        let maxCell: GridCell
        if sides.count == 2 {
            guard let parsed = parseCell(sides[1].trimmingCharacters(in: .whitespaces)) else {
                issues.append(.init(line: line, message: "region max cell malformed"))
                return
            }
            maxCell = parsed
        } else {
            maxCell = minCell
        }
        current?.minCell = minCell
        current?.maxCell = maxCell
    }

    private func parseCell(_ text: String) -> GridCell? {
        let parts = text.split(separator: ",")
        guard parts.count == 2,
              let row = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let col = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              row >= 0, col >= 0
        else { return nil }
        return GridCell(row: row, col: col)
    }

    private mutating func apply(shortcut value: String, line: Int) {
        switch ShortcutSpec.parse(value) {
        case .success(let spec):
            current?.shortcut = spec
        case .failure(let err):
            issues.append(.init(line: line, message: err.message))
        }
    }

    // MARK: - Block commit

    private mutating func commitCurrent() {
        guard let block = current else { return }
        current = nil

        guard let rows = block.rows, let cols = block.cols else {
            issues.append(.init(line: block.startLine, message: "[snap] missing `grid`"))
            return
        }
        guard let minCell = block.minCell, let maxCell = block.maxCell else {
            issues.append(.init(line: block.startLine, message: "[snap] missing `region`"))
            return
        }
        guard maxCell.row < rows, maxCell.col < cols else {
            issues.append(.init(
                line: block.startLine,
                message: "region cells exceed the \(rows)x\(cols) grid"
            ))
            return
        }
        let spec = SnapSpec(rows: rows, cols: cols, minCell: minCell, maxCell: maxCell)
        snaps.append(Snap(spec: spec, shortcut: block.shortcut))
    }

    private struct Block {
        let startLine: Int
        var rows: Int?
        var cols: Int?
        var minCell: GridCell?
        var maxCell: GridCell?
        var shortcut: ShortcutSpec?
    }
}

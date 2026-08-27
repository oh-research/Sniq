import Foundation

// MARK: - ShortcutSpec

/// A keyboard shortcut bound to a `Snap`. Matched inside the
/// CGEventTap callback by `(keyCode, modifiers)` so both fields are
/// primitive/Sendable and serialization is trivial.
struct ShortcutSpec: Codable, Equatable, Hashable, Sendable {
    let keyCode: Int64
    let modifiers: PressedModifiers

    /// Apple-style glyph form for UI labels, e.g. `⌃⌥⇧ L`.
    var displayString: String {
        let glyph = ShortcutKeyTable.glyph(for: keyCode) ?? "?"
        let mods = modifiers.symbol
        return mods.isEmpty ? glyph : "\(mods) \(glyph)"
    }

    /// `.sniq` file form, e.g. `ctrl+opt+shift+L`. Round-trips with `parse`.
    var sniqString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option)  { parts.append("opt") }
        if modifiers.contains(.shift)   { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        if let name = ShortcutKeyTable.name(for: keyCode) {
            parts.append(name.uppercased())
        }
        return parts.joined(separator: "+")
    }

    // MARK: - Validation

    /// Rejects only the "no modifiers" case (would collide with typing).
    /// grip/flip/stretch overlap is intentionally allowed — drag gestures
    /// are mouseDown-driven and do not conflict with keyDown events.
    func validate() -> ValidationError? {
        if modifiers.isEmpty { return .noModifiers }
        return nil
    }

    enum ValidationError: Error, Equatable {
        case noModifiers

        var message: String {
            switch self {
            case .noModifiers:
                return "Shortcut needs at least one modifier (⌃ ⌥ ⇧ ⌘)."
            }
        }
    }

    // MARK: - Parsing (.sniq input)

    static func parse(_ raw: String) -> Result<ShortcutSpec, ParseError> {
        let cleaned = raw.replacingOccurrences(of: " ", with: "+")
        let tokens = cleaned
            .split(separator: "+", omittingEmptySubsequences: true)
            .map { $0.lowercased() }
        guard !tokens.isEmpty else { return .failure(.empty) }

        var mods: PressedModifiers = []
        var keyToken: String?

        for token in tokens {
            switch token {
            case "cmd", "command":
                mods.insert(.command)
            case "ctrl", "control":
                mods.insert(.control)
            case "opt", "option", "alt":
                mods.insert(.option)
            case "shift":
                mods.insert(.shift)
            default:
                if keyToken != nil { return .failure(.multipleKeys) }
                keyToken = token
            }
        }

        guard let keyToken else { return .failure(.noKey) }
        guard let keyCode = ShortcutKeyTable.keyCode(for: keyToken) else {
            return .failure(.unknownKey(keyToken))
        }
        let spec = ShortcutSpec(keyCode: keyCode, modifiers: mods)
        if let err = spec.validate() { return .failure(.invalid(err)) }
        return .success(spec)
    }

    enum ParseError: Error, Equatable {
        case empty
        case noKey
        case multipleKeys
        case unknownKey(String)
        case invalid(ValidationError)

        var message: String {
            switch self {
            case .empty:                return "shortcut is empty"
            case .noKey:                return "shortcut has no key (only modifiers)"
            case .multipleKeys:         return "shortcut has more than one non-modifier key"
            case .unknownKey(let tok):  return "unknown key \"\(tok)\""
            case .invalid(let err):     return err.message
            }
        }
    }
}

// MARK: - Key name table

/// Bidirectional map between `CGKeyCode` virtual codes and the short
/// names used in `.sniq` files. Glyphs are the Apple-style symbols
/// shown in the UI. Kept as a single source of truth so parser, writer,
/// and display-string helpers never drift.
enum ShortcutKeyTable {

    static func keyCode(for name: String) -> Int64? {
        entries.first { $0.name == name }?.keyCode
    }

    static func name(for keyCode: Int64) -> String? {
        entries.first { $0.keyCode == keyCode }?.name
    }

    static func glyph(for keyCode: Int64) -> String? {
        entries.first { $0.keyCode == keyCode }?.glyph
    }

    private struct Entry {
        let keyCode: Int64
        let name: String   // sniq-file token (lowercase)
        let glyph: String  // UI display
    }

    /// Ordered by category so a casual reader can verify coverage at a glance.
    /// Virtual key codes from Carbon `kVK_*` constants.
    private static let entries: [Entry] = [
        // Letters
        .init(keyCode:  0, name: "a", glyph: "A"),
        .init(keyCode: 11, name: "b", glyph: "B"),
        .init(keyCode:  8, name: "c", glyph: "C"),
        .init(keyCode:  2, name: "d", glyph: "D"),
        .init(keyCode: 14, name: "e", glyph: "E"),
        .init(keyCode:  3, name: "f", glyph: "F"),
        .init(keyCode:  5, name: "g", glyph: "G"),
        .init(keyCode:  4, name: "h", glyph: "H"),
        .init(keyCode: 34, name: "i", glyph: "I"),
        .init(keyCode: 38, name: "j", glyph: "J"),
        .init(keyCode: 40, name: "k", glyph: "K"),
        .init(keyCode: 37, name: "l", glyph: "L"),
        .init(keyCode: 46, name: "m", glyph: "M"),
        .init(keyCode: 45, name: "n", glyph: "N"),
        .init(keyCode: 31, name: "o", glyph: "O"),
        .init(keyCode: 35, name: "p", glyph: "P"),
        .init(keyCode: 12, name: "q", glyph: "Q"),
        .init(keyCode: 15, name: "r", glyph: "R"),
        .init(keyCode:  1, name: "s", glyph: "S"),
        .init(keyCode: 17, name: "t", glyph: "T"),
        .init(keyCode: 32, name: "u", glyph: "U"),
        .init(keyCode:  9, name: "v", glyph: "V"),
        .init(keyCode: 13, name: "w", glyph: "W"),
        .init(keyCode:  7, name: "x", glyph: "X"),
        .init(keyCode: 16, name: "y", glyph: "Y"),
        .init(keyCode:  6, name: "z", glyph: "Z"),
        // Digits
        .init(keyCode: 29, name: "0", glyph: "0"),
        .init(keyCode: 18, name: "1", glyph: "1"),
        .init(keyCode: 19, name: "2", glyph: "2"),
        .init(keyCode: 20, name: "3", glyph: "3"),
        .init(keyCode: 21, name: "4", glyph: "4"),
        .init(keyCode: 23, name: "5", glyph: "5"),
        .init(keyCode: 22, name: "6", glyph: "6"),
        .init(keyCode: 26, name: "7", glyph: "7"),
        .init(keyCode: 28, name: "8", glyph: "8"),
        .init(keyCode: 25, name: "9", glyph: "9"),
        // Arrows
        .init(keyCode: 123, name: "left",  glyph: "←"),
        .init(keyCode: 124, name: "right", glyph: "→"),
        .init(keyCode: 126, name: "up",    glyph: "↑"),
        .init(keyCode: 125, name: "down",  glyph: "↓"),
        // Function keys
        .init(keyCode: 122, name: "f1",  glyph: "F1"),
        .init(keyCode: 120, name: "f2",  glyph: "F2"),
        .init(keyCode:  99, name: "f3",  glyph: "F3"),
        .init(keyCode: 118, name: "f4",  glyph: "F4"),
        .init(keyCode:  96, name: "f5",  glyph: "F5"),
        .init(keyCode:  97, name: "f6",  glyph: "F6"),
        .init(keyCode:  98, name: "f7",  glyph: "F7"),
        .init(keyCode: 100, name: "f8",  glyph: "F8"),
        .init(keyCode: 101, name: "f9",  glyph: "F9"),
        .init(keyCode: 109, name: "f10", glyph: "F10"),
        .init(keyCode: 103, name: "f11", glyph: "F11"),
        .init(keyCode: 111, name: "f12", glyph: "F12"),
        // Specials
        .init(keyCode:  49, name: "space",    glyph: "Space"),
        .init(keyCode:  48, name: "tab",      glyph: "⇥"),
        .init(keyCode:  36, name: "return",   glyph: "↵"),
        .init(keyCode:  53, name: "esc",      glyph: "⎋"),
        .init(keyCode:  51, name: "delete",   glyph: "⌫"),
        .init(keyCode: 116, name: "pageup",   glyph: "⇞"),
        .init(keyCode: 121, name: "pagedown", glyph: "⇟"),
        .init(keyCode: 115, name: "home",     glyph: "↖"),
        .init(keyCode: 119, name: "end",      glyph: "↘"),
    ]
}

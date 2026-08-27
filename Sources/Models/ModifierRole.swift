@preconcurrency import Cocoa

// MARK: - ModifierRole

/// Semantic role a modifier key plays in sniq's gesture system.
///
/// - `grip`:    activator — the user is about to manipulate a window
/// - `flip`:    switches from primary to secondary grid layout
/// - `stretch`: qualifier required for keyboard arrow snap (and for
///              mouse resize in later milestones)
enum ModifierRole: String, CaseIterable, Sendable {
    case grip
    case flip
    case stretch

    /// User-facing label for the Settings UI.
    var label: String {
        switch self {
        case .grip:    return "Grip"
        case .flip:    return "Flip"
        case .stretch: return "Stretch"
        }
    }
}

// MARK: - ModifierKey

/// A single physical modifier key on the Mac keyboard. Used for
/// Settings UI rendering and for translating user-visible labels.
enum ModifierKey: String, CaseIterable, Sendable {
    case shift
    case control
    case option
    case command
    case function

    /// User-facing symbol for Settings UI and shortcut strings.
    var symbol: String {
        switch self {
        case .shift:    return "⇧"
        case .control:  return "⌃"
        case .option:   return "⌥"
        case .command:  return "⌘"
        case .function: return "fn"
        }
    }
}

// MARK: - PressedModifiers

/// Allocation-free bitmask of modifier keys. Used on hot paths
/// (CGEventTap callback, keyboard snap coordinator) where Set allocation
/// per event would be wasteful. Bridges to `Set<ModifierKey>` at the UI
/// boundary via `asSet` / `init(_:)`.
struct PressedModifiers: OptionSet, Sendable, Hashable, Codable {
    let rawValue: UInt8

    static let shift    = PressedModifiers(rawValue: 1 << 0)
    static let control  = PressedModifiers(rawValue: 1 << 1)
    static let option   = PressedModifiers(rawValue: 1 << 2)
    static let command  = PressedModifiers(rawValue: 1 << 3)
    static let function = PressedModifiers(rawValue: 1 << 4)

    /// Reads modifier state from `CGEventFlags` as seen inside the
    /// CGEventTap callback. Other bits (caps lock, numeric pad, etc.)
    /// are intentionally ignored.
    init(cgFlags: CGEventFlags) {
        var set: PressedModifiers = []
        if cgFlags.contains(.maskShift)       { set.insert(.shift) }
        if cgFlags.contains(.maskControl)     { set.insert(.control) }
        if cgFlags.contains(.maskAlternate)   { set.insert(.option) }
        if cgFlags.contains(.maskCommand)     { set.insert(.command) }
        if cgFlags.contains(.maskSecondaryFn) { set.insert(.function) }
        self = set
    }

    /// Reads modifier state from an `NSEvent.ModifierFlags` value, as
    /// produced by AppKit event monitors used by the shortcut recorder.
    init(nsFlags: NSEvent.ModifierFlags) {
        var set: PressedModifiers = []
        if nsFlags.contains(.shift)    { set.insert(.shift) }
        if nsFlags.contains(.control)  { set.insert(.control) }
        if nsFlags.contains(.option)   { set.insert(.option) }
        if nsFlags.contains(.command)  { set.insert(.command) }
        if nsFlags.contains(.function) { set.insert(.function) }
        self = set
    }

    init(_ keys: Set<ModifierKey>) {
        var set: PressedModifiers = []
        for key in keys { set.insert(Self(key)) }
        self = set
    }

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Iterable view for SwiftUI `ForEach` and validation messages.
    var asSet: Set<ModifierKey> {
        var result: Set<ModifierKey> = []
        if contains(.shift)    { result.insert(.shift) }
        if contains(.control)  { result.insert(.control) }
        if contains(.option)   { result.insert(.option) }
        if contains(.command)  { result.insert(.command) }
        if contains(.function) { result.insert(.function) }
        return result
    }

    fileprivate init(_ key: ModifierKey) {
        switch key {
        case .shift:    self = .shift
        case .control:  self = .control
        case .option:   self = .option
        case .command:  self = .command
        case .function: self = .function
        }
    }

    /// Concatenated symbols in canonical order (`⇧⌃⌥⌘fn`). Empty for `[]`.
    var symbol: String {
        ModifierKey.allCases.filter { asSet.contains($0) }.map(\.symbol).joined()
    }

    /// Symbols joined with `" + "`. Used in Settings labels where keys are
    /// composed into a readable shortcut string.
    var formatted: String {
        ModifierKey.allCases.filter { asSet.contains($0) }.map(\.symbol).joined(separator: " + ")
    }
}

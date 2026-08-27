@preconcurrency import Cocoa

// MARK: - Grid

struct GridCell: Equatable, Hashable, Codable, Sendable {
    let row: Int
    let col: Int
}

struct GridConfiguration: Equatable, Sendable {
    var rows: Int
    var cols: Int
    var gap: CGFloat
    var padding: CGFloat
}

/// Identifies which of the two configurable layouts is currently active.
/// `.primary` is the default layout; `.secondary` is activated by the
/// `Flip` modifier (Ctrl by default) on keyboard shortcuts.
enum LayoutVariant: Sendable {
    case primary
    case secondary
}

// MARK: - Window

struct TrackedWindow: @unchecked Sendable {
    let windowID: CGWindowID
    let axElement: AXUIElement
    let pid: pid_t
    let originalFrame: CGRect
}

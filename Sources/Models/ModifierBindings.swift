import Foundation

// MARK: - ModifierBindings

/// User-configurable mapping of each `ModifierRole` to the set of physical
/// modifier keys that fulfill that role. Determines which key combinations
/// trigger sniq gestures.
///
/// Defaults: `Grip = ⌃ Control`, `Flip = ⌥ Option`, `Stretch = ⌘ Command`.
/// Grip is the one modifier that must be held for a drag to be claimed;
/// Flip and Stretch are optional add-ons pressed alongside Grip to switch
/// layouts or select multi-cell regions. The user may rebind any of the
/// three in Settings — in-app / marketing copy reads the current binding
/// via `PreferencesStore.bindings.<role>.formatted`.
struct ModifierBindings: Equatable, Sendable {
    var grip: PressedModifiers
    var flip: PressedModifiers
    var stretch: PressedModifiers

    static let `default` = ModifierBindings(
        grip:    .control,
        flip:    .option,
        stretch: .command
    )

    func keys(for role: ModifierRole) -> PressedModifiers {
        switch role {
        case .grip:    return grip
        case .flip:    return flip
        case .stretch: return stretch
        }
    }
}

// MARK: - Validation

extension ModifierBindings {
    enum ValidationIssue: Equatable, Sendable {
        case empty(ModifierRole)
        case overlap(ModifierRole, ModifierRole)
    }

    /// Returns every reason the binding is unusable. Empty array means valid.
    /// A binding is valid iff every role has at least one key AND no two
    /// roles share any key (disjoint sets).
    func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for role in ModifierRole.allCases where keys(for: role).isEmpty {
            issues.append(.empty(role))
        }
        let pairs: [(ModifierRole, ModifierRole)] = [
            (.grip, .flip), (.grip, .stretch), (.flip, .stretch)
        ]
        for (lhs, rhs) in pairs where !keys(for: lhs).isDisjoint(with: keys(for: rhs)) {
            issues.append(.overlap(lhs, rhs))
        }
        return issues
    }

    var isValid: Bool { validate().isEmpty }
}

// MARK: - Persistence

extension ModifierBindings {
    /// Reads bindings from `UserDefaults`. Safe to call from any thread,
    /// including the CGEventTap callback, because `UserDefaults` access is
    /// thread-safe and we avoid touching the `@MainActor` store.
    ///
    /// Strips `fn` from all roles because macOS auto-sets `maskSecondaryFn`
    /// on arrow keypresses (a compatibility carry-over from old MacBook
    /// keyboards), which makes any `fn`-bound role match too permissively.
    /// Migrates contaminated state back to persistence so subsequent
    /// reads don't pay for the re-strip.
    ///
    /// Falls back to `.default` when the stripped candidate fails
    /// validation (defensive against corrupted state after an app upgrade).
    static func load(from defaults: UserDefaults = .standard) -> ModifierBindings {
        let raw = ModifierBindings(
            grip:    Self.read(defaults, key: Keys.grip),
            flip:    Self.read(defaults, key: Keys.flip),
            stretch: Self.read(defaults, key: Keys.stretch)
        )
        let stripped = raw.strippingFunction()
        if stripped != raw { stripped.save(to: defaults) }
        return stripped.isValid ? stripped : .default
    }

    private func strippingFunction() -> ModifierBindings {
        ModifierBindings(
            grip:    grip.subtracting(.function),
            flip:    flip.subtracting(.function),
            stretch: stretch.subtracting(.function)
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(Int(grip.rawValue),    forKey: Keys.grip)
        defaults.set(Int(flip.rawValue),    forKey: Keys.flip)
        defaults.set(Int(stretch.rawValue), forKey: Keys.stretch)
    }

    private static func read(_ defaults: UserDefaults, key: String) -> PressedModifiers {
        PressedModifiers(rawValue: UInt8(clamping: defaults.integer(forKey: key)))
    }

    enum Keys {
        static let grip    = "modifierBinding.grip"
        static let flip    = "modifierBinding.flip"
        static let stretch = "modifierBinding.stretch"
    }
}

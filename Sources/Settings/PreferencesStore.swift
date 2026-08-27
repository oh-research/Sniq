import SwiftUI

@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    @AppStorage("primaryRows") var primaryRows: Int = 1
    @AppStorage("primaryCols") var primaryCols: Int = 3
    @AppStorage("secondaryRows") var secondaryRows: Int = 2
    @AppStorage("secondaryCols") var secondaryCols: Int = 2
    @AppStorage("gridGap") var gap: Double = 0
    @AppStorage("gridPadding") var padding: Double = 0
    @AppStorage("onboardingCompleted") var onboardingCompleted: Bool = false

    /// Role-to-modifier bindings. Readable directly by SwiftUI so labels
    /// update immediately when `updateBindings(_:)` writes new values.
    @Published private(set) var bindings: ModifierBindings = .load()

    private init() {
        Self.migrateLegacyGridKeysIfNeeded()
        Self.purgeRetiredKeys()
    }

    /// Persists new bindings to UserDefaults and publishes the change so
    /// SwiftUI observers (Settings labels) rebuild. Coordinators on the
    /// event-tap thread re-read via `ModifierBindings.load()` on each
    /// event, so they pick up the new binding without observing here.
    func updateBindings(_ new: ModifierBindings) {
        new.save()
        bindings = new
    }

    /// Returns the grid configuration for the given variant. `gap` and
    /// `padding` are shared across layouts.
    func configuration(for variant: LayoutVariant) -> GridConfiguration {
        switch variant {
        case .primary:
            return GridConfiguration(
                rows: primaryRows,
                cols: primaryCols,
                gap: CGFloat(gap),
                padding: CGFloat(padding)
            )
        case .secondary:
            return GridConfiguration(
                rows: secondaryRows,
                cols: secondaryCols,
                gap: CGFloat(gap),
                padding: CGFloat(padding)
            )
        }
    }

    // MARK: - Legacy migration

    /// Migrates pre-v1.1.0 `gridRows`/`gridCols` into the new primary/secondary
    /// keys on first launch after upgrade. Secondary is initialized as the
    /// row/col swap of the legacy value so users immediately see a meaningful
    /// difference when holding Opt. Legacy keys are left in place as a rollback
    /// safety net.
    /// Drops UserDefaults keys retired by later builds (pre-Snap
    /// keyboard toggles, the persisted enable switch replaced by the
    /// session-scoped `PauseState`). Silent — upgrades shouldn't prompt.
    private static func purgeRetiredKeys() {
        let defaults = UserDefaults.standard
        let retired = [
            "keyboardSnapEnabled",
            "keyboardSnapInterceptInTextFields",
            "isEnabled",
        ]
        for key in retired {
            defaults.removeObject(forKey: key)
        }
    }

    private static func migrateLegacyGridKeysIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "primaryRows") == nil else { return }

        let legacyRows = (defaults.object(forKey: "gridRows") as? Int) ?? 2
        let legacyCols = (defaults.object(forKey: "gridCols") as? Int) ?? 3

        defaults.set(legacyRows, forKey: "primaryRows")
        defaults.set(legacyCols, forKey: "primaryCols")
        defaults.set(legacyCols, forKey: "secondaryRows")
        defaults.set(legacyRows, forKey: "secondaryCols")
    }
}

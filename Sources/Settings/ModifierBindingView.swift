import SwiftUI

/// Settings sub-view for rebinding the Grip / Flip / Stretch roles to
/// physical modifier keys. Each role renders as a card with an icon,
/// description, and four keycap toggles (⇧⌃⌥⌘). Invalid selections
/// are kept in-memory so the user can recover, but never persisted —
/// event-tap coordinators always read a valid binding.
struct ModifierBindingView: View {

    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var draft: ModifierBindings = .load()

    // `.function` is intentionally omitted: macOS auto-sets the fn flag
    // on arrow keypresses, which would make a fn-bound role match too
    // permissively. `ModifierBindings.load()` also strips it on load.
    private static let keys: [ModifierKey] = [.shift, .control, .option, .command]
    private static let roles: [ModifierRole] = [.grip, .flip, .stretch]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.roles, id: \.self) { role in
                roleCard(role)
            }
            footer
        }
        .padding(.vertical, 4)
        .focusEffectDisabled()
    }

    // MARK: - Role card

    private func roleCard(_ role: ModifierRole) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: Self.icon(for: role))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(role.label)
                        .font(.subheadline.weight(.semibold))
                }
                Text(Self.describe(role))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
            }
            .frame(width: 170, alignment: .leading)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ForEach(Self.keys, id: \.self) { key in
                    ModifierCap(
                        symbol: key.symbol,
                        isOn: draft.keys(for: role).contains(PressedModifiers([key]))
                    ) {
                        apply(role: role, key: key, include: !draft.keys(for: role).contains(PressedModifiers([key])))
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let message = firstIssueMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button {
                resetToDefaults()
            } label: {
                Label("Reset", systemImage: "arrow.uturn.backward")
            }
            .controlSize(.small)
        }
        .padding(.top, 2)
    }

    // MARK: - Role metadata

    private static func icon(for role: ModifierRole) -> String {
        switch role {
        case .grip:    return "hand.point.up.braille.fill"
        case .flip:    return "rectangle.2.swap"
        case .stretch: return "arrow.up.left.and.arrow.down.right"
        }
    }

    private static func describe(_ role: ModifierRole) -> String {
        switch role {
        case .grip:    return "Hold to grab a window"
        case .flip:    return "Swap primary ↔ secondary layout"
        case .stretch: return "Select a multi-cell region"
        }
    }

    // MARK: - State bridging

    private func apply(role: ModifierRole, key: ModifierKey, include: Bool) {
        var updated = draft.keys(for: role)
        let mask = PressedModifiers([key])
        if include {
            updated.insert(mask)
        } else {
            updated.subtract(mask)
        }
        draft = ModifierBindings(
            grip:    role == .grip    ? updated : draft.grip,
            flip:    role == .flip    ? updated : draft.flip,
            stretch: role == .stretch ? updated : draft.stretch
        )
        if draft.isValid {
            prefs.updateBindings(draft)
        }
    }

    private func resetToDefaults() {
        draft = .default
        prefs.updateBindings(draft)
    }

    // MARK: - Validation message

    private var firstIssueMessage: String? {
        guard let issue = draft.validate().first else { return nil }
        switch issue {
        case .empty(let role):
            return "\(role.label) needs at least one modifier"
        case .overlap(let a, let b):
            let shared = draft.keys(for: a).intersection(draft.keys(for: b))
            return "\(a.label) and \(b.label) share \(shared.symbol)"
        }
    }
}

// MARK: - Modifier keycap toggle

/// Pressable keycap button that flips `isOn` on click. Accent-filled
/// when on, neutral-outlined when off. Matches the look of `KeycapView`
/// used elsewhere in Settings / Snaps.
private struct ModifierCap: View {

    let symbol: String
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(isOn ? Color.accentColor : .primary)
                .frame(width: 32, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(fillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(strokeColor, lineWidth: isOn ? 1.5 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var fillColor: Color {
        if isOn { return Color.accentColor.opacity(0.18) }
        if hovering { return Color.secondary.opacity(0.12) }
        return Color(NSColor.controlBackgroundColor)
    }

    private var strokeColor: Color {
        isOn ? Color.accentColor : Color.secondary.opacity(0.35)
    }
}

import SwiftUI

/// Placeholder row shown inside Saved / Recent sections when the list is
/// empty. Pairs a hint icon with guidance for the user's next step.
struct EmptyStateRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

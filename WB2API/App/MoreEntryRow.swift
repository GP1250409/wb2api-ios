import SwiftUI

/// 「更多」页的单行入口。
struct MoreEntryRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: Metrics.m) {
            Image(systemName: systemImage)
                .foregroundStyle(Accent.primary)
                .frame(width: Metrics.l)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Metrics.xs)
        .frame(minHeight: Metrics.minTap)
    }
}

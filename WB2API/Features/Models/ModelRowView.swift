import SwiftUI

/// 模型行：ID、倍率、上下文长度，默认/繁忙用语义标签。
struct ModelRowView: View {
    let model: ModelInfo

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(model.displayID)
                    .font(.callout.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if model.isDefault == true {
                    StatusTag(text: "默认", systemImage: "star.fill", tint: Accent.primary)
                }
                if model.isBusy {
                    StatusTag(text: "繁忙", systemImage: "hourglass", tint: .orange)

                }
            }

            if let description = model.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: Metrics.m) {
                Label("倍率 \(model.creditMultiplierText)", systemImage: "creditcard")
                Label("上下文 \(model.contextText)", systemImage: "ruler")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, Metrics.xs)
        .accessibilityElement(children: .combine)
    }
}

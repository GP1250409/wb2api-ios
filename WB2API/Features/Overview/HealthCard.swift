import SwiftUI

/// 健康度主卡：健康环 + 「8/11 健康」+ 一句人话状态。
struct HealthCard: View {
    let digest: OverviewDigest

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.m) {
            RingGauge(progress: digest.healthyRatio, lineWidth: 11) {
                VStack(spacing: 0) {
                    Text(digest.healthLabel)
                        .font(.metric(.title2))
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text("健康")
                        .font(.tag)
                        .foregroundStyle(.secondary)
                }
                .padding(Metrics.m)
            }
            .frame(width: 122, height: 122)

            VStack(alignment: .leading, spacing: Metrics.s) {
                Text(digest.headline)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Label(digest.coolingLine, systemImage: "hourglass")
                        .foregroundStyle(digest.cooling > 0 ? Color.orange : Color.secondary)

                    Label(digest.disabledLine, systemImage: "pause.circle")
                        .foregroundStyle(digest.disabled > 0 ? Color.red : Color.secondary)

                    Label(digest.checkinLine, systemImage: "checkmark.seal")
                        .foregroundStyle(.secondary)

                    if digest.inFlightFull {
                        Label("并发已满，新请求会排队", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.footnote)
                .labelStyle(.titleAndIcon)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard()
        .motion(Motion.emphasized, value: digest)
    }
}

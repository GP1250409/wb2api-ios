import SwiftUI

/// 队列状态卡：运行状态（脉冲）、排队数、并发与开始时间。
struct QueueStatusCard: View {
    let running: Bool
    let total: Int
    let concurrency: Int?
    let startedAt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack(alignment: .center, spacing: Metrics.s) {
                Text("任务队列")
                    .font(.headline)
                Spacer(minLength: Metrics.xs)
                StatusTag(
                    text: running ? "运行中" : "空闲",
                    systemImage: running ? "bolt.fill" : "pause.fill",
                    tint: running ? Accent.primary : .secondary
                )
                .symbolEffect(.pulse, options: .repeating, isActive: running)
            }

            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(total, format: .number)
                    .font(.metric())
                    .foregroundStyle(running ? Accent.primary : .primary)
                    .contentTransition(.numericText())
                Text("项排队")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Divider()

            VStack(spacing: Metrics.s) {
                LabeledContent("并发数") {
                    Text(concurrencyText)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("开始时间") {
                    Text(startedText)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .motion(Motion.numeric, value: total)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("任务队列\(running ? "运行中" : "空闲")，\(total) 项排队")
    }

    private var concurrencyText: String {
        guard let concurrency, concurrency > 0 else { return "—" }
        return "\(concurrency)"
    }

    /// 后端空值时间是 `0001-01-01T00:00:00Z`，不展示。
    private var startedText: String {
        guard
            let startedAt,
            let date = Fmt.parse(startedAt),
            Calendar.current.component(.year, from: date) > 2001
        else {
            return "—"
        }
        return Fmt.ago(startedAt)
    }
}

#Preview {
    VStack(spacing: Metrics.m) {
        QueueStatusCard(running: true, total: 12, concurrency: 4, startedAt: nil)
        QueueStatusCard(running: false, total: 0, concurrency: 0, startedAt: nil)
    }
    .padding()
}

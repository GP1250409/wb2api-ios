import SwiftUI

/// 概览的用量趋势面板：最近 24 个小时桶的 token 柱状图 + 三个汇总指标。
///
/// 数据来自 `usage.series`（`{t:"2026-10-24T02", total_tokens, requests}`），
/// 概览本来就会拉 usage（为了「今日消耗」），这里复用同一份快照，不额外请求。
struct UsageTrendCard: View {
    let usage: UsageSnapshot?

    private var buckets: [UsagePoint] {
        Array((usage?.series ?? []).suffix(24))
    }

    /// 柱体数据：索引 + token 数（ForEach 用 Identifiable，避免元组 key path）。
    private struct TrendBar: Identifiable {
        let id: Int
        let tokens: Int
    }

    private var bars: [TrendBar] {
        buckets.enumerated().map { TrendBar(id: $0.offset, tokens: $0.element.totalTokens ?? $0.element.tokens ?? 0) }
    }

    private var values: [Int] { bars.map(\.tokens) }

    private var peak: Int {
        values.max() ?? 0
    }

    private var totalTokens: Int {
        values.reduce(0, +)
    }

    private var totalRequests: Int {
        buckets.compactMap(\.requests).reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            SectionHeader(title: "用量趋势", subtitle: subtitle)

            if buckets.isEmpty {
                ContentUnavailableView(
                    "还没有用量数据",
                    systemImage: "chart.bar.xaxis",
                    description: Text("产生请求后，这里会按小时显示 token 消耗")
                )
                .padding(.vertical, Metrics.m)
                .glassCard()
            } else {
                chart
                metrics
            }
        }
    }

    private var subtitle: String {
        buckets.isEmpty ? "最近 24 小时" : "最近 \(buckets.count) 小时 · 峰值 \(Fmt.compact(peak))"
    }

    private var chart: some View {
        VStack(spacing: Metrics.xs) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(bars) { bar in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(index: bar.id))
                        .frame(height: barHeight(bar))
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 76, alignment: .bottom)

            HStack {
                Text(hourLabel(buckets.first?.t))
                Spacer()
                Text(hourLabel(buckets[buckets.count / 2].t))
                Spacer()
                Text(hourLabel(buckets.last?.t))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
        .padding(Metrics.m)
        .glassCard(padding: 0, cornerRadius: Metrics.radiusM)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 \(buckets.count) 小时用量趋势，峰值 \(Fmt.compact(peak)) tokens")
    }

    private var metrics: some View {
        HStack(spacing: Metrics.s) {
            metric(title: "24h tokens", value: Fmt.compact(totalTokens))
            metric(title: "请求数", value: Fmt.compact(totalRequests))
            metric(title: "峰值/小时", value: Fmt.compact(peak))
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.callout.bold().monospacedDigit())
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.s)
        .glassCard(padding: 0, cornerRadius: Metrics.radiusS)
    }

    // MARK: - 绘制细节

    private func barHeight(_ bar: TrendBar) -> CGFloat {
        guard peak > 0 else { return 2 }
        return max(2, CGFloat(bar.tokens) / CGFloat(peak) * 76)
    }

    /// 最近的桶用主色，往前依次变淡，形成时间梯度。
    private func barColor(index: Int) -> Color {
        let ratio = Double(index + 1) / Double(max(buckets.count, 1))
        return Accent.primary.opacity(0.25 + 0.6 * ratio)
    }

    /// "2026-10-24T02" → "02时"；解析失败原样返回。
    private func hourLabel(_ raw: String?) -> String {
        guard let raw, raw.count >= 13 else { return raw ?? "—" }
        let hour = raw.suffix(2)
        return "\(hour)时"
    }
}

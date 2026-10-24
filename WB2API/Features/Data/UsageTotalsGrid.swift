import SwiftUI

/// 用量总览：两列指标块。
struct UsageTotalsGrid: View {
    let totals: UsageTotals?

    private let columns = [
        GridItem(.flexible(), spacing: Metrics.s),
        GridItem(.flexible(), spacing: Metrics.s)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Metrics.s) {
            StatTile(title: "请求数", value: Fmt.compact(totals?.requests))
            StatTile(title: "总 Token", value: Fmt.compact(totals?.totalTokens))
            StatTile(
                title: "积分消耗",
                value: Fmt.creditsDouble(totals?.credits),
                tint: Accent.primary
            )
            StatTile(title: "错误数", value: Fmt.compact(totals?.errors))
            StatTile(title: "平均延迟", value: Fmt.latency(totals?.avgLatencyMs))
            StatTile(title: "缓存命中", value: Fmt.rate(totals?.cacheHitRate))
        }
    }
}

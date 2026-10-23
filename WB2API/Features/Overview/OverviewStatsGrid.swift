import SwiftUI

/// 概览指标网格：积分 / 请求 / 成功率 / 签到进度。
struct OverviewStatsGrid: View {
    let digest: OverviewDigest

    private let columns = [
        GridItem(.flexible(), spacing: Metrics.s),
        GridItem(.flexible(), spacing: Metrics.s)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Metrics.s) {
            StatTile(
                title: "剩余积分",
                value: Fmt.credits(digest.totalCredits),
                caption: "全部账号合计",
                tint: Accent.primary
            )
            StatTile(
                title: "今日消耗",
                value: Fmt.compact(digest.todayTokens ?? 0),
                caption: digest.todayTokens == nil ? "暂无用量数据" : "tokens · 今日"
            )
            StatTile(
                title: "成功率",
                value: Fmt.percent(digest.successRate, digits: 1),
                caption: "成功 / 请求"
            )
            StatTile(
                title: "今日签到",
                value: "\(digest.checkinDone)/\(digest.total)",
                caption: digest.checkinCaption
            )
        }
        .motion(Motion.numeric, value: digest)
    }
}

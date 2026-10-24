import SwiftUI

struct HubOverviewDashboard: View {
    let client: HubClient
    @StateObject private var model = HubDashboardModel()
    var body: some View {
        NavigationStack {
            HubOverviewContent(data: model.overview, updated: model.updated, isLoading: model.isLoading, error: model.error, warnings: model.warnings) {
                Task { await model.loadOverview(client: client) }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await model.loadOverview(client: client) }
            .refreshable { await model.loadOverview(client: client) }
        }
    }
}

/// Pure presentation view: shared visual primitives, no credentials or hidden network work.
struct HubOverviewContent: View {
    let data: HubOverviewPresentation?
    var updated: Date?
    var isLoading = false
    var error: String?
    var warnings: [String] = []
    var reload: () -> Void = {}
    private var summary: String {
        guard let total = data?.total else { return isLoading ? "正在读取账号池…" : "账号池状态一览" }
        return "\(total) 个账号 · \(data?.ready.map(String.init) ?? "—") 个可用"
    }
    var body: some View {
        HubDashboardSurface {
            HubDashboardHeading(title: "概览", subtitle: summary, updated: updated, isLoading: isLoading, reload: reload)
            if let error { ErrorBanner(message: error, retry: reload) }
            if data == nil && isLoading {
                LoadingSkeleton(rows: 5)
            } else {
                HubHealthSummaryCard(data: data)
                HubOverviewStatsGrid(data: data)
                HubCooldownsCard(cooldowns: data?.cooldowns())
                if let trend = data?.trend {
                    UsageTrendCard(usage: trend, maximumBuckets: 25, subtitleOverride: "最近 24 小时 · 完成请求 · 设备时区")
                    Text("趋势统计完成请求的 Tokens；上方今日消耗还包含上游已计费的失败消耗，两者窗口与口径不同。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        SectionHeader(title: "用量趋势", subtitle: "最近 24 小时")
                        Label("后端尚未返回有效的小时趋势数据", systemImage: "chart.bar.xaxis")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).glassCard()
                }
            }
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { item in
                        Label(item.element, systemImage: "exclamationmark.triangle").font(.footnote)
                    }
                }
                .foregroundStyle(.secondary).glassCard()
            }
        }
    }
}

struct HubUsageDashboard: View {
    let client: HubClient
    @StateObject private var model = HubDashboardModel()
    @State private var range: UsageRange = .days7
    @State private var dimension: UsageDimension = .account
    var body: some View {
        NavigationStack {
            HubUsageContent(presentation: model.usage, range: $range, dimension: $dimension, updated: model.updated, isLoading: model.isLoading, error: model.error) {
                Task { await model.loadUsage(client: client, range: range) }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: range) { await model.loadUsage(client: client, range: range) }
            .refreshable { await model.loadUsage(client: client, range: range) }
        }
    }
}

struct HubUsageContent: View {
    let presentation: HubUsagePresentation?
    @Binding var range: UsageRange
    @Binding var dimension: UsageDimension
    var updated: Date?
    var isLoading = false
    var error: String?
    var reload: () -> Void = {}
    private var selected: HubUsagePresentation? {
        guard let presentation, presentation.window.range == range else { return nil }
        return presentation
    }
    var body: some View {
        HubDashboardSurface {
            HubDashboardHeading(title: "数据", updated: updated, isLoading: isLoading, reload: reload)
            UsageRangePicker(selection: $range).disabled(isLoading)
            if let error { ErrorBanner(message: error, retry: reload) }
            if let selected {
                UsageRangeSummaryCard(range: range, totals: selected.snapshot.totals, subtitleOverride: selected.window.subtitle, perDayOverride: selected.perDay, missingAsDash: true)
                Picker("统计维度", selection: $dimension) {
                    ForEach(UsageDimension.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                UsageTotalsGrid(totals: selected.snapshot.totals, useTokenUnits: true)
                groupsChart(selected)
                VStack(alignment: .leading, spacing: Metrics.s) {
                    LabeledContent("估算费用（CNY）", value: HubDashboardFormat.money(selected.costCNY))
                    Text("请求数＝成功＋错误，不含客户端取消。Tokens 包含上游已计费的失败消耗；估算费用仅为后端已计价部分。")
                        .font(.caption).foregroundStyle(.secondary)
                    if range == .all {
                        Text("Hub 未提供全部记录覆盖的起点，总计日均不做推测。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .glassCard()
            } else if isLoading {
                LoadingSkeleton(rows: 6)
            } else {
                UsageRangeSummaryCard(range: range, totals: nil, subtitleOverride: range == .all ? "Hub 可用全量记录" : range.subtitle, perDayOverride: "—", missingAsDash: true)
                UsageTotalsGrid(totals: nil, useTokenUnits: true)
                Text("该区间尚未成功读取，请刷新。不会用另一个区间或零值顶替。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func groupsChart(_ selected: HubUsagePresentation) -> some View {
        let raw: [UsageGroup]? = {
            switch dimension {
            case .account: return selected.snapshot.byAccount
            case .model: return selected.snapshot.byModel
            case .realm: return selected.snapshot.byRealm
            }
        }()
        if let raw {
            let valid = raw.filter { $0.requests != nil }.sorted {
                if $0.requests != $1.requests { return ($0.requests ?? 0) > ($1.requests ?? 0) }
                return ($0.key ?? "") < ($1.key ?? "")
            }
            UsageBarChart(title: dimension.chartTitle, groups: valid)
            if valid.count < raw.count {
                Text("部分分组没有返回请求计数，图表未将它们当作零请求。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.s) {
                SectionHeader(title: dimension.chartTitle)
                Text("后端未提供此维度的区间分组数据。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).glassCard()
        }
    }
}

import SwiftUI
import Charts

/// 「数据」Tab：用量总览 + 积分消耗分布 + 历史入口。
///
/// 数据源只有 `client.usage()`（一次请求拿到 totals / byAccount / byModel / byRealm），
/// 分段切换维度不重新请求，只切同一份快照里的数组。
struct DataView: View {
    @Environment(SessionStore.self) private var session

    private var client: APIClient? { session.client() }

    /// 统计维度。
    private enum Scope: String, CaseIterable, Identifiable {
        case account = "按账号"
        case model = "按模型"
        case realm = "按域"

        var id: String { rawValue }
    }

    /// 图表一行的数据。
    private struct ScopeBar: Identifiable {
        let id: String
        let label: String
        let credits: Double
    }

    @State private var loader = Loader<UsageSnapshot>()
    @State private var scope: Scope = .account
    @State private var toast: Toast?
    @State private var savingSnapshot = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    scopePicker
                    stateContent
                }
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.xl)
            }
            .background(Palette.background)
            .navigationTitle("数据")
            .toolbar { toolbarContent }
            .refreshable { await reload() }
            .task {
                if loader.isEmpty { await reload() }
            }
            .toast($toast)
        }
    }

    // MARK: - 顶部

    private var scopePicker: some View {
        Picker("统计维度", selection: $scope) {
            ForEach(Scope.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .motion(Motion.spring, value: scope)
    }

    @ViewBuilder
    private var stateContent: some View {
        if let error = loader.error {
            // ErrorBanner 自带 16pt 横向内边距，抵消外层 padding 避免双重缩进
            ErrorBanner(message: error) {
                Task { await reload() }
            }
            .padding(.horizontal, -Spacing.m)
        }

        if loader.isLoading && loader.value == nil {
            SkeletonRows(count: 5)
                .padding(.horizontal, -Spacing.m)
        } else if let snapshot = loader.value {
            totalsGrid(snapshot)
            chartCard(snapshot)
            linksCard
        } else if loader.error == nil {
            EmptyBox(
                title: "暂无用量数据",
                message: "网关产生一次请求后，这里会出现统计",
                systemImage: "chart.bar"
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    // MARK: - 总量四宫格

    private func totalsGrid(_ snapshot: UsageSnapshot) -> some View {
        let totals = snapshot.totals
        let errorCount = totals?.errors ?? 0
        let successRate: Double? = {
            guard let requests = totals?.requests, requests > 0 else { return nil }
            return Double(requests - errorCount) / Double(requests)
        }()

        return VStack(alignment: .leading, spacing: Spacing.s) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Spacing.s),
                    GridItem(.flexible(), spacing: Spacing.s)
                ],
                spacing: Spacing.s
            ) {
                StatTile(
                    label: "请求数",
                    value: Fmt.compact(totals?.requests),
                    caption: "累计"
                )
                StatTile(
                    label: "错误数",
                    value: Fmt.compact(totals?.errors),
                    tint: errorCount > 0 ? Palette.danger : Palette.textPrimary,
                    caption: "累计"
                )
                StatTile(
                    label: "平均延迟",
                    value: Fmt.latency(totals?.avgLatencyMs),
                    caption: "全池平均"
                )
                StatTile(
                    label: "成功率",
                    value: Fmt.percent(successRate),
                    tint: (successRate ?? 1) < 0.95 ? Palette.warning : Palette.success,
                    caption: "成功 / 请求"
                )
            }

            HStack(spacing: Spacing.m) {
                Text("TOKENS \(Fmt.compact(totals?.totalTokens))")
                Text("积分 \(Fmt.creditsDouble(totals?.credits))")
                Text("缓存 \(Fmt.percent(totals?.cacheHitRate))")
            }
            .font(Typography.caption)
            .foregroundStyle(Palette.textSecondary)
            .monospacedDigit()
            .padding(.horizontal, Spacing.xs)
        }
    }

    // MARK: - 条形图

    private func chartCard(_ snapshot: UsageSnapshot) -> some View {
        let rows = bars(from: snapshot)

        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("积分消耗")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(scope.rawValue)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            if rows.isEmpty {
                EmptyBox(
                    title: "暂无消耗",
                    message: "换一个维度，或等网关跑完几个请求",
                    systemImage: "chart.bar"
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(rows) { row in
                    BarMark(
                        x: .value("积分", row.credits),
                        y: .value("对象", shortLabel(row.label))
                    )
                    .foregroundStyle(Palette.accent)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(rows.count) * 34 + 28)
                .animation(Motion.numeric, value: rows.map(\.credits))
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    /// 把当前维度的分组转成按积分降序的柱（最多 8 条，避免图过高）。
    private func bars(from snapshot: UsageSnapshot) -> [ScopeBar] {
        let groups: [UsageGroup]
        switch scope {
        case .account:
            groups = snapshot.byAccount ?? []
        case .model:
            groups = snapshot.byModel ?? []
        case .realm:
            groups = snapshot.byRealm ?? []
        }

        let bars: [ScopeBar] = groups.compactMap { group in
            guard let key = group.key, !key.isEmpty else { return nil }
            return ScopeBar(id: key, label: key, credits: group.credits ?? 0)
        }
        .filter { $0.credits > 0 }
        .sorted { $0.credits > $1.credits }

        return Array(bars.prefix(8))
    }

    /// Y 轴标签截断到 12 字（超出用省略号），否则长模型名会把绘图区挤没。
    private func shortLabel(_ text: String) -> String {
        text.count > 12 ? String(text.prefix(11)) + "…" : text
    }

    // MARK: - 历史入口

    private var linksCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                CreditHistoryView()
            } label: {
                linkRow(title: "积分历史", detail: "最近 100 条积分变动", icon: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Palette.divider)
                .frame(height: 1)
                .padding(.leading, Spacing.m + 32 + Spacing.s)

            NavigationLink {
                BalanceHistoryView()
            } label: {
                linkRow(title: "余额趋势", detail: "多账号余额曲线与日均消耗", icon: "chart.xyaxis.line")
            }
            .buttonStyle(.plain)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    private func linkRow(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 32, height: 32)
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            Spacer(minLength: Spacing.s)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(Spacing.m)
        .contentShape(Rectangle())
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await saveSnapshot() }
            } label: {
                if savingSnapshot {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .disabled(client == nil || savingSnapshot)
            .accessibilityLabel("保存快照")
        }
    }

    // MARK: - 动作

    private func reload() async {
        guard let client else {
            toast = Toast(kind: .failure, text: "服务器地址无效，请先在设置里填写")
            return
        }
        await loader.load { try await client.usage() }
    }

    private func saveSnapshot() async {
        guard let client else {
            toast = Toast(kind: .failure, text: "服务器地址无效，请先在设置里填写")
            return
        }
        savingSnapshot = true
        defer { savingSnapshot = false }
        do {
            try await client.postVoid("panel/api/usage/save")
            withAnimation(Motion.spring) {
                toast = Toast(kind: .success, text: "快照已保存")
            }
            await reload()
        } catch {
            toast = Toast(kind: .failure, text: apiMessage(error))
        }
    }

    private func apiMessage(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}

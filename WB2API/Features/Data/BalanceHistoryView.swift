import SwiftUI
import Charts

/// 余额趋势：7 / 14 / 30 天的多账号余额折线（`client.balanceHistory(days:)`）。
///
/// 配色只用 `Palette` 的四个语义色循环（accent / success / warning / info），
/// 不引入新色值；折线数量超过 4 条时颜色会重复，此时靠下方图例 + 账号行区分。
struct BalanceHistoryView: View {
    @Environment(SessionStore.self) private var session

    private var client: APIClient? { session.client() }

    private struct SeriesPoint: Identifiable {
        let id: String
        let date: Date
        let balance: Int
    }

    private struct ChartSeries: Identifiable {
        let id: String
        let name: String
        let color: Color
        let points: [SeriesPoint]
    }

    /// 折线循环色（仅使用设计系统里的四种语义色）。
    private static let seriesColors: [Color] = [
        Palette.accent,
        Palette.success,
        Palette.warning,
        Palette.info
    ]

    private static let dayOptions = [7, 14, 30]

    @State private var days = 7
    @State private var loader = Loader<BalanceHistory>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                dayPicker

                if let error = loader.error {
                    ErrorBanner(message: error) {
                        Task { await reload() }
                    }
                    .padding(.horizontal, -Spacing.m)
                }

                if loader.isLoading && loader.value == nil {
                    SkeletonRows(count: 5)
                        .padding(.horizontal, -Spacing.m)
                } else if let history = loader.value {
                    let series = chartSeries(from: history)
                    if series.isEmpty {
                        EmptyBox(
                            title: "暂无余额数据",
                            message: "开启余额刷新后，网关会定期记录各账号余额",
                            systemImage: "chart.xyaxis.line"
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        chartCard(series: series)
                        accountsCard(history: history, series: series)
                    }
                } else if loader.error == nil {
                    EmptyBox(title: "暂无余额数据", systemImage: "tray")
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(Spacing.m)
        }
        .background(Palette.background)
        .navigationTitle("余额趋势")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task(id: days) {
            await reload()
        }
    }

    // MARK: - 天数选择

    private var dayPicker: some View {
        Picker("时间范围", selection: $days) {
            ForEach(Self.dayOptions, id: \.self) { option in
                Text("\(option) 天").tag(option)
            }
        }
        .pickerStyle(.segmented)
        .motion(Motion.spring, value: days)
    }

    // MARK: - 折线图

    private func chartCard(series: [ChartSeries]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("余额曲线")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("最近 \(days) 天")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            Chart {
                ForEach(series) { item in
                    ForEach(item.points) { point in
                        LineMark(
                            x: .value("时间", point.date),
                            y: .value("余额", point.balance)
                        )
                        .foregroundStyle(item.color)
                        .interpolationMethod(.monotone)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)
            .animation(Motion.numeric, value: series.count)

            legend(series)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    private func legend(_ series: [ChartSeries]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(series.prefix(8)) { item in
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 7, height: 7)
                    Text(item.name)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - 账号余额

    private func accountsCard(history: BalanceHistory, series: [ChartSeries]) -> some View {
        let list = history.series ?? []

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("账号余额")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("\(list.count) 个账号")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.bottom, Spacing.xs)

            ForEach(Array(list.indices), id: \.self) { index in
                accountRow(list[index], color: color(for: list[index].id, in: series))
                if index < list.count - 1 {
                    Rectangle()
                        .fill(Palette.divider)
                        .frame(height: 1)
                }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    private func accountRow(_ series: BalanceSeries, color: Color) -> some View {
        let average = dailyAverage(series, days: days)

        return HStack(spacing: Spacing.s) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(series.name ?? shortUID(series.uid))
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Spacing.xs) {
                    Text("日均消耗 \(Fmt.creditsDouble(average))")
                    if let min = series.min, let max = series.max {
                        Text("· \(Fmt.credits(min))–\(Fmt.credits(max))")
                    }
                }
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
            }

            Spacer(minLength: Spacing.s)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.credits(series.current))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                Text(changeText(series.change))
                    .font(Typography.caption)
                    .foregroundStyle((series.change ?? 0) >= 0 ? Palette.success : Palette.danger)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, Spacing.s)
    }

    // MARK: - 数据整形

    private func chartSeries(from history: BalanceHistory) -> [ChartSeries] {
        let list = history.series ?? []
        var result: [ChartSeries] = []

        for (index, item) in list.enumerated() {
            let points: [SeriesPoint] = (item.points ?? []).compactMap { point in
                guard let stamp = point.t, let credits = point.c else { return nil }
                return SeriesPoint(
                    id: "\(item.uid ?? String(index))-\(stamp)",
                    date: Date(timeIntervalSince1970: Double(stamp) / 1000),
                    balance: credits
                )
            }
            .sorted { $0.date < $1.date }

            guard !points.isEmpty else { continue }
            result.append(
                ChartSeries(
                    id: item.id,
                    name: item.name ?? shortUID(item.uid),
                    color: Self.seriesColors[result.count % Self.seriesColors.count],
                    points: points
                )
            )
        }

        return result
    }

    private func color(for id: String, in series: [ChartSeries]) -> Color {
        series.first(where: { $0.id == id })?.color ?? Palette.textTertiary
    }

    /// 日均消耗 = 每日 consumed 求和 / 天数（缺失的日不算，仍按整天数平均）。
    private func dailyAverage(_ series: BalanceSeries, days: Int) -> Double? {
        let daily = series.daily ?? []
        guard !daily.isEmpty else { return nil }
        let consumed = daily.compactMap(\.consumed).reduce(0, +)
        return Double(consumed) / Double(max(days, 1))
    }

    private func shortUID(_ uid: String?) -> String {
        guard let uid, !uid.isEmpty else { return "—" }
        return String(uid.prefix(8))
    }

    private func changeText(_ change: Int?) -> String {
        guard let change else { return "—" }
        return change >= 0 ? "+\(Fmt.credits(change))" : Fmt.credits(change)
    }

    // MARK: - 动作

    private func reload() async {
        guard let client else { return }
        await loader.load { try await client.balanceHistory(days: days) }
    }
}

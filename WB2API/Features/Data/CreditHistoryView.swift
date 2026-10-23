import SwiftUI

/// 积分历史：最近 100 条积分变动（`client.creditHistory(limit: 100)`）。
///
/// 后端 `CreditEntry.ts` 是 epoch 毫秒，而 `Fmt.clock` 接收服务器原始时间字符串，
/// 所以这里先把毫秒转成 ISO8601 字符串再交给 `Fmt.clock`，保证时间格式统一。
struct CreditHistoryView: View {
    @Environment(SessionStore.self) private var session

    private var client: APIClient? { session.client() }

    @State private var loader = Loader<CreditHistory>()
    @State private var toast: Toast?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if let error = loader.error {
                    ErrorBanner(message: error) {
                        Task { await reload() }
                    }
                    .padding(.horizontal, -Spacing.m)
                }

                if loader.isLoading && loader.value == nil {
                    SkeletonRows(count: 6)
                        .padding(.horizontal, -Spacing.m)
                } else if let history = loader.value {
                    summary(history)
                    rows(history)
                } else if loader.error == nil {
                    EmptyBox(
                        title: "暂无积分记录",
                        message: "消耗或充值后会出现在这里",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(Spacing.m)
        }
        .background(Palette.background)
        .navigationTitle("积分历史")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task {
            if loader.isEmpty { await reload() }
        }
        .toast($toast)
    }

    // MARK: - 汇总

    private var entries: [CreditEntry] {
        (loader.value?.entries ?? []).sorted { ($0.ts ?? 0) > ($1.ts ?? 0) }
    }

    private func summary(_ history: CreditHistory) -> some View {
        let list = history.entries ?? []
        let net = list.compactMap(\.credits).reduce(0, +)
        let tokens = list.compactMap(\.tokens).reduce(0, +)

        return HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("共 \(list.count) 条")
                    .font(Typography.metricSmall)
                    .foregroundStyle(Palette.textPrimary)
                Text("limit \(history.limit ?? list.count)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            Spacer(minLength: Spacing.s)

            VStack(alignment: .trailing, spacing: 2) {
                Text(signed(net))
                    .font(Typography.metricSmall)
                    .foregroundStyle(net >= 0 ? Palette.success : Palette.danger)
                Text("净变动 · \(Fmt.compact(tokens)) tokens")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    // MARK: - 列表

    @ViewBuilder
    private func rows(_ history: CreditHistory) -> some View {
        let list = entries
        if list.isEmpty {
            EmptyBox(
                title: "暂无积分记录",
                message: "网关还没有产生计费请求",
                systemImage: "tray"
            )
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(list.indices), id: \.self) { index in
                    row(list[index])
                    if index < list.count - 1 {
                        Rectangle()
                            .fill(Palette.divider)
                            .frame(height: 1)
                            .padding(.leading, Spacing.m)
                    }
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
    }

    private func row(_ entry: CreditEntry) -> some View {
        let credits = entry.credits
        let tint: Color = (credits ?? 0) >= 0 ? Palette.success : Palette.danger

        return HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.model ?? entry.uid ?? "未知来源")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Spacing.xs) {
                    Text(clockText(entry.ts))
                    if let uid = entry.uid, entry.model != nil {
                        Text("·")
                        Text(String(uid.prefix(8)))
                    }
                    if let note = entry.note, !note.isEmpty {
                        Text("·")
                        Text(note).lineLimit(1)
                    }
                }
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
            }

            Spacer(minLength: Spacing.s)

            VStack(alignment: .trailing, spacing: 3) {
                Text(creditsText(credits))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                Text("\(Fmt.compact(entry.tokens)) tokens")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(Spacing.m)
        .contentShape(Rectangle())
    }

    // MARK: - 格式化

    private func clockText(_ ts: Int?) -> String {
        guard let ts else { return "—" }
        let date = Date(timeIntervalSince1970: Double(ts) / 1000)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return Fmt.clock(iso.string(from: date))
    }

    private func creditsText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return signed(value)
    }

    private func signed(_ value: Double) -> String {
        String(format: "%+.2f", value)
    }

    // MARK: - 动作

    private func reload() async {
        guard let client else {
            toast = Toast(kind: .failure, text: "服务器地址无效，请先在设置里填写")
            return
        }
        await loader.load { try await client.creditHistory(limit: 100) }
    }
}

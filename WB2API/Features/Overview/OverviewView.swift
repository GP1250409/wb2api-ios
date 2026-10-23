import SwiftUI

// MARK: - 概览

struct OverviewView: View {
    @Environment(SessionStore.self) private var session

    @State private var loader = Loader<OverviewResponse>()
    @State private var toast: Toast?
    @State private var running: BatchCommand?

    private var client: APIClient? { session.client() }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: Spacing.s),
            GridItem(.flexible(), spacing: Spacing.s)
        ]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.m) {
                header
                    .padding(.horizontal, Spacing.m)
                    .staggeredAppear(index: 0)

                if loader.value == nil {
                    if let message = loader.error ?? setupError {
                        ErrorBanner(message: message) {
                            Task { await refresh() }
                        }
                    } else {
                        SkeletonRows(count: 5)
                    }
                } else if let data = loader.value {
                    if data.accounts.isEmpty {
                        emptyPool
                    } else {
                        if let message = loader.error {
                            ErrorBanner(message: message) {
                                Task { await refresh() }
                            }
                        }

                        healthCard(data)
                            .padding(.horizontal, Spacing.m)
                            .staggeredAppear(index: 1)

                        metricsGrid(data)
                            .padding(.horizontal, Spacing.m)
                            .staggeredAppear(index: 2)

                        batchSection
                            .staggeredAppear(index: 3)

                        previewSection(data)
                            .staggeredAppear(index: 4)
                    }
                }
            }
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xl)
        }
        .background(Palette.background)
        .refreshable { await refresh() }
        .task { await refresh() }
        .onAppear { refreshIfStale() }
        .toast($toast)
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .center, spacing: Spacing.s) {
                Text("概览")
                    .font(Typography.display)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: Spacing.s)
                BrandMark(size: 26)
            }

            Text(subtitle)
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .contentTransition(.numericText())
                .motion(Motion.gentle, value: subtitle)
        }
    }

    private var subtitle: String {
        guard let data = loader.value else {
            return loader.isLoading ? "正在读取账号池…" : "账号池状态一览"
        }
        let healthy = data.healthy ?? data.accounts.filter(\.isHealthy).count
        return "\(data.total) 个账号 · \(healthy) 个可用"
    }

    private var emptyPool: some View {
        EmptyBox(
            title: "还没有账号",
            message: "在网页端登录 WorkBuddy 账号后，这里会自动出现",
            systemImage: "person.crop.circle.badge.plus"
        )
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    // MARK: 健康度主卡

    private func healthCard(_ data: OverviewResponse) -> some View {
        let total = data.total
        let healthy = data.healthy ?? data.accounts.filter(\.isHealthy).count
        let cooling = data.cooling ?? data.accounts.filter(\.isCooling).count
        let disabled = data.disabled ?? data.accounts.filter(\.isDisabled).count
        let ratio = total > 0 ? Double(healthy) / Double(total) : 0

        return HStack(alignment: .center, spacing: Spacing.m) {
            RingGauge(progress: ratio, lineWidth: 10, tint: Palette.accentGradient) {
                VStack(spacing: 0) {
                    Text("\(healthy)/\(total)")
                        .font(.system(size: 21, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText())
                    Text("健康")
                        .font(Typography.label)
                        .tracking(0.6)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(width: 112, height: 112)
            .motion(Motion.emphasized, value: ratio)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("健康账号 \(healthy) 个，共 \(total) 个")

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(headline(healthy: healthy, total: total))
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                CoolingStatusLine(count: cooling, until: earliestCoolingUntil(data.accounts))
                disabledLine(count: disabled)

                Text(updatedText)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.m)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    private func headline(healthy: Int, total: Int) -> String {
        guard total > 0 else { return "等待账号接入" }
        if healthy == total { return "池子状态良好" }
        let ratio = Double(healthy) / Double(total)
        if ratio >= 0.6 { return "部分账号需要关注" }
        return "池子压力较大"
    }

    private func disabledLine(count: Int) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: count > 0 ? "pause.circle" : "checkmark.circle")
                .font(.system(size: 11, weight: .semibold))
            Text(count > 0 ? "\(count) 个账号已禁用" : "没有禁用的账号")
                .font(Typography.caption)
        }
        .foregroundStyle(count > 0 ? Palette.danger : Palette.textSecondary)
    }

    private var updatedText: String {
        guard let updated = loader.lastUpdated else { return "尚未同步" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "更新于 \(formatter.string(from: updated))"
    }

    /// 取最早恢复的那个冷却账号的原始时间戳，交给 Fmt.countdown 统一格式化。
    private func earliestCoolingUntil(_ accounts: [Account]) -> String? {
        let now = Date()
        let candidates: [(Date, String)] = accounts.compactMap { account in
            guard account.isCooling,
                  let raw = account.until,
                  let date = Fmt.parse(raw),
                  date > now else { return nil }
            return (date, raw)
        }
        return candidates.min { $0.0 < $1.0 }?.1
    }

    // MARK: 指标网格

    private func metricsGrid(_ data: OverviewResponse) -> some View {
        let total = data.total
        let healthy = data.healthy ?? data.accounts.filter(\.isHealthy).count
        let cooling = data.cooling ?? data.accounts.filter(\.isCooling).count
        let disabled = data.disabled ?? data.accounts.filter(\.isDisabled).count
        let requests = data.accounts.compactMap { $0.tokenUsage?.requestCount }.reduce(0, +)
        let ratio = total > 0 ? Double(healthy) / Double(total) : 0

        return LazyVGrid(columns: gridColumns, spacing: Spacing.s) {
            StatTile(
                label: "账号总数",
                value: "\(total)",
                caption: "池内全部账号"
            )
            StatTile(
                label: "可用",
                value: "\(healthy)",
                tint: Palette.success,
                caption: "健康占比 \(Fmt.percent(ratio, digits: 0))"
            )
            StatTile(
                label: "冷却",
                value: "\(cooling)",
                tint: cooling > 0 ? Palette.warning : Palette.textSecondary,
                caption: cooling > 0 ? "等待自动恢复" : "暂无冷却"
            )
            StatTile(
                label: "禁用",
                value: "\(disabled)",
                tint: disabled > 0 ? Palette.danger : Palette.textSecondary,
                caption: disabled > 0 ? "需要手动恢复" : "暂无禁用"
            )
            StatTile(
                label: "积分剩余",
                value: Fmt.credits(data.totalCredits),
                tint: Palette.accent,
                caption: "全部账号合计"
            )
            StatTile(
                label: "累计请求",
                value: Fmt.compact(requests),
                caption: "按已上报用量统计"
            )
        }
    }

    // MARK: 批量操作

    private var batchSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "批量操作", subtitle: "一次下发给全部账号")

            LazyVGrid(columns: gridColumns, spacing: Spacing.s) {
                ForEach(BatchCommand.allCases) { command in
                    Button {
                        Task { await runBatch(command) }
                    } label: {
                        if running == command {
                            HStack(spacing: Spacing.xs) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(command.title)
                                    .font(Typography.callout)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 24)
                        } else {
                            Label(command.title, systemImage: command.icon)
                                .font(Typography.callout)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: 24)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Palette.accent)
                    .controlSize(.large)
                    .disabled(running != nil)
                    .accessibilityHint(command.hint)
                }
            }
            .padding(.horizontal, Spacing.m)
            .motion(Motion.spring, value: running)
        }
    }

    // MARK: 账号预览

    private func previewSection(_ data: OverviewResponse) -> some View {
        let preview = Array(data.accounts.prefix(5))

        return VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(
                title: "账号池",
                subtitle: "前 \(preview.count) 个账号 · 共 \(data.total) 个"
            )

            VStack(spacing: 0) {
                ForEach(Array(preview.enumerated()), id: \.element.id) { index, account in
                    OverviewAccountRow(account: account)
                        .staggeredAppear(index: index)

                    if index < preview.count - 1 {
                        Rectangle()
                            .fill(Palette.divider)
                            .frame(height: 1)
                            .padding(.leading, Spacing.m + 28 + Spacing.s)
                    }
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .padding(.horizontal, Spacing.m)

            Text("到「账号」页查看全部账号，支持搜索、筛选与单号操作")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.xxs)
        }
    }

    // MARK: 数据

    private func refresh() async {
        guard let client else {
            setupError = "服务器地址无效，请到「更多 · 设置」中检查"
            toast = Toast(kind: .failure, text: "服务器地址无效")
            return
        }
        setupError = nil
        await loader.load { try await client.overview() }
    }

    private func refreshIfStale() {
        guard loader.value != nil else { return }
        guard let updated = loader.lastUpdated,
              Date().timeIntervalSince(updated) > 20 else { return }
        Task { await refresh() }
    }

    private func runBatch(_ command: BatchCommand) async {
        guard let client, running == nil else { return }
        running = command
        defer { running = nil }

        do {
            let result = try await client.batch(command.rawValue)
            if let object = result.objectValue, object["ok"]?.boolValue == false {
                let message = object["error"]?.stringValue ?? "服务器拒绝了该操作"
                toast = Toast(kind: .failure, text: "\(command.title)失败：\(message)")
            } else {
                let message = result.objectValue?["message"]?.stringValue ?? ""
                toast = Toast(kind: .success, text: message.isEmpty ? "\(command.title)已下发" : message)
                await loader.load { try await client.overview() }
            }
        } catch {
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            toast = Toast(kind: .failure, text: "\(command.title)失败：\(message)")
        }
    }
}

// MARK: - 批量指令

private enum BatchCommand: String, CaseIterable, Identifiable {
    case checkin = "checkin_all"
    case travel = "travel_all"
    case activity = "activity_all"
    case keepalive = "keepalive_all"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .checkin: return "全部签到"
        case .travel: return "旅行巡检"
        case .activity: return "活跃上报"
        case .keepalive: return "全部保活"
        }
    }

    var icon: String {
        switch self {
        case .checkin: return "checkmark.seal"
        case .travel: return "airplane"
        case .activity: return "waveform.path.ecg"
        case .keepalive: return "heart.text.square"
        }
    }

    var hint: String {
        switch self {
        case .checkin: return "为所有账号领取每日签到积分"
        case .travel: return "逐个账号执行旅行巡检"
        case .activity: return "上报账号活跃状态"
        case .keepalive: return "刷新会话，避免账号掉线"
        }
    }
}

// MARK: - 冷却状态行（只让这一行按秒重绘）

private struct CoolingStatusLine: View {
    let count: Int
    let until: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: Spacing.xs) {
                Image(systemName: count > 0 ? "hourglass" : "checkmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(message)
                    .font(Typography.caption)
                    .lineLimit(2)
            }
            .foregroundStyle(count > 0 ? Palette.warning : Palette.textSecondary)
        }
    }

    private var message: String {
        guard count > 0 else { return "没有冷却中的账号" }
        if let until, let left = Fmt.countdown(until: until) {
            return "\(count) 个账号冷却中，\(left)后恢复"
        }
        return "\(count) 个账号冷却中，等待自动恢复"
    }
}

// MARK: - 预览行

private struct OverviewAccountRow: View {
    let account: Account

    private var tint: Color {
        Palette.statusColor(
            healthy: account.isHealthy,
            cooling: account.isCooling,
            disabled: account.isDisabled
        )
    }

    private var stateText: String {
        if account.isDisabled { return "禁用" }
        if account.isCooling { return "冷却" }
        return "可用"
    }

    private var icon: String {
        if account.isDisabled { return "pause.fill" }
        if account.isCooling { return "hourglass" }
        return "checkmark"
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityLabel(Fmt.accountState(account))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs + 2) {
                    Text(account.displayName)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    StatusPill(text: stateText, color: tint)
                }

                CreditBar(progress: account.creditProgress, tint: tint, height: 3)
            }

            Spacer(minLength: Spacing.s)

            VStack(alignment: .trailing, spacing: 0) {
                Text(Fmt.credits(account.credits))
                    .font(Typography.callout)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.numericText())
                Text("积分")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s + 2)
        .accessibilityElement(children: .combine)
    }
}

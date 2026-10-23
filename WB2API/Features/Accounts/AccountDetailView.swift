import Foundation
import SwiftUI

// MARK: - 账号详情

struct AccountDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    private let account: Account

    @State private var loader = Loader<StatusResponse>()
    @State private var toast: Toast?
    @State private var busy: AccountCommand?
    @State private var confirmRemove = false
    @State private var errorExpanded = false
    @State private var setupError: String?

    init(account: Account) {
        self.account = account
    }

    private var client: APIClient? { session.client() }

    /// 用 uid 在最新状态里找同号，找不到时退回列表传入的快照。
    private var current: Account {
        loader.value?.accounts.first(where: { $0.uid == account.uid }) ?? account
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.m) {
                header
                    .staggeredAppear(index: 0)

                if let message = loader.error ?? setupError {
                    ErrorBanner(message: message) {
                        Task { await refresh() }
                    }
                }

                creditsCard
                    .staggeredAppear(index: 1)

                usageCard
                    .staggeredAppear(index: 2)

                modelCostsCard
                    .staggeredAppear(index: 3)

                rateLimitCard
                    .staggeredAppear(index: 4)

                if let lastError = lastErrorDate {
                    errorCard(lastError)
                        .staggeredAppear(index: 5)
                }

                actionsCard
                    .staggeredAppear(index: lastErrorDate == nil ? 5 : 6)
            }
            .padding(.vertical, Spacing.m)
        }
        .background(Palette.background)
        .navigationTitle(current.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { await refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新", systemImage: "arrow.clockwise") {
                    Task { await refresh() }
                }
                .disabled(loader.isLoading)
            }
        }
        .toast($toast)
        .confirmationDialog("移除账号", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("移除", role: .destructive) {
                Task { await removeAccount() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("移除后需要重新登录该账号才能恢复，历史用量记录会保留。")
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(current.displayName)
                    .font(Typography.displaySmall)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)

                StatusPill(text: stateText, color: stateColor, icon: stateIcon)
            }

            HStack(spacing: Spacing.s) {
                Text(current.realmLabel)
                    .font(Typography.label)
                    .tracking(0.4)
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, 3)
                    .background(Palette.accentSoft, in: Capsule())

                Text("UID \(shortUID)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Text("最后活跃 \(Fmt.ago(current.lastSuccess)) · 累计成功 \(Fmt.compact(current.successCount)) 次")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)

            if current.isCooling, let until = current.until, let left = Fmt.countdown(until: until) {
                Text("冷却中，\(left)后恢复")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.warning)
            }

            if let expires = current.creditsEarliestExpiry, let days = remainingDays(expires), days <= 3 {
                Label(expiryWarning(days), systemImage: "exclamationmark.circle")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .padding(.horizontal, Spacing.m)
        .motion(Motion.spring, value: stateText)
    }

    private var shortUID: String {
        String(current.uid.prefix(8))
    }

    private var stateText: String {
        if current.isDisabled { return "已禁用" }
        if current.isCooling { return "冷却中" }
        return "可用"
    }

    private var stateColor: Color {
        Palette.statusColor(
            healthy: current.isHealthy,
            cooling: current.isCooling,
            disabled: current.isDisabled
        )
    }

    private var stateIcon: String {
        if current.isDisabled { return "pause.fill" }
        if current.isCooling { return "hourglass" }
        return "checkmark.circle.fill"
    }

    private func remainingDays(_ raw: String) -> Int? {
        guard let date = Fmt.parse(raw) else { return nil }
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return 0 }
        return Int(ceil(seconds / 86_400))
    }

    private func expiryWarning(_ days: Int) -> String {
        if days <= 0 { return "最早一笔积分今天到期" }
        return "最早一笔积分 \(days) 天后到期"
    }

    // MARK: 积分卡

    private var creditsCard: some View {
        cardChrome {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text("积分")
                        .font(Typography.label)
                        .tracking(0.6)
                        .foregroundStyle(Palette.textSecondary)

                    Spacer()

                    Text("剩余 \(Fmt.percent(current.creditProgress, digits: 0))")
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(Fmt.credits(current.credits))
                        .font(Typography.metric)
                        .foregroundStyle(Palette.accent)
                        .contentTransition(.numericText())

                    Text("/ \(Fmt.credits(current.creditsTotal))")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                .motion(Motion.numeric, value: current.credits)

                CreditBar(progress: current.creditProgress, height: 6)

                Rectangle()
                    .fill(Palette.divider)
                    .frame(height: 1)
                    .padding(.vertical, Spacing.xxs)

                HStack(alignment: .firstTextBaseline) {
                    Text("最早到期")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)

                    Spacer()

                    Text(expiryText)
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                }
            }
        }
    }

    private var expiryText: String {
        guard let expiry = current.creditsEarliestExpiry else { return "—" }
        let day = Fmt.day(expiry)
        if let remain = current.creditsEarliestRemaining {
            return "\(day) · \(Fmt.credits(remain)) 积分"
        }
        return day
    }

    // MARK: 用量卡

    private var usageCard: some View {
        cardChrome {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("用量")
                    .font(Typography.label)
                    .tracking(0.6)
                    .foregroundStyle(Palette.textSecondary)

                if let usage = current.tokenUsage {
                    KeyValueRow(label: "请求次数", value: Fmt.compact(usage.requestCount))
                    KeyValueRow(label: "输入 tokens", value: Fmt.compact(usage.promptTokens))
                    KeyValueRow(label: "输出 tokens", value: Fmt.compact(usage.completionTokens))
                    KeyValueRow(label: "合计 tokens", value: Fmt.compact(usage.totalTokens))
                    KeyValueRow(label: "最近延迟", value: Fmt.latency(usage.lastLatencyMs.map { Double($0) }))
                    KeyValueRow(label: "生成速度", value: speedText(usage.lastTokensPerSecond))
                    KeyValueRow(label: "最近模型", value: usage.lastModel ?? "—")
                    KeyValueRow(label: "最近使用", value: Fmt.ago(usage.lastUsedAt))
                } else {
                    Text("暂无用量记录")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.vertical, Spacing.s)
                }
            }
        }
    }

    private func speedText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f tok/s", value)
    }

    // MARK: 通用卡片外观

    private func cardChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.m)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .padding(.horizontal, Spacing.m)
    }

    // MARK: 模型成本

    private var modelCostsCard: some View {
        let costs = (current.modelCosts ?? []).sorted { ($0.costPer1k ?? 0) > ($1.costPer1k ?? 0) }
        let maxCost = costs.compactMap(\.costPer1k).max() ?? 0

        return cardChrome {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("模型成本")
                    .font(Typography.label)
                    .tracking(0.6)
                    .foregroundStyle(Palette.textSecondary)

                if costs.isEmpty {
                    Text("暂无成本记录")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.vertical, Spacing.s)
                } else {
                    ForEach(costs) { cost in
                        VStack(alignment: .leading, spacing: Spacing.xxs + 1) {
                            HStack(spacing: Spacing.s) {
                                Text(cost.model ?? "未知模型")
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(1)

                                Spacer(minLength: Spacing.s)

                                Text(costText(cost.costPer1k))
                                    .font(Typography.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.textSecondary)
                            }

                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Palette.surfaceAlt)
                                    Capsule()
                                        .fill(Palette.accent.opacity(0.75))
                                        .frame(width: max(2, proxy.size.width * ratio(cost.costPer1k, max: maxCost)))
                                }
                            }
                            .frame(height: 4)
                            .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    private func costText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f / 1k", value)
    }

    private func ratio(_ value: Double?, max maximum: Double) -> Double {
        guard let value, maximum > 0 else { return 0 }
        return min(max(value / maximum, 0), 1)
    }

    // MARK: 限流中的模型

    private var rateLimitCard: some View {
        let models = current.rateLimitedModels ?? []

        return cardChrome {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text("限流中模型")
                        .font(Typography.label)
                        .tracking(0.6)
                        .foregroundStyle(Palette.textSecondary)

                    Spacer()

                    if !models.isEmpty {
                        Text("\(models.count) 个")
                            .font(Typography.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.warning)
                    }
                }

                if models.isEmpty {
                    Text("当前没有被限流的模型")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.vertical, Spacing.s)
                } else {
                    ForEach(models) { item in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(item.model ?? "未知模型")
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(1)

                                if let reason = item.reason, !reason.isEmpty {
                                    Text(reason)
                                        .font(Typography.caption)
                                        .foregroundStyle(Palette.textTertiary)
                                        .lineLimit(2)
                                }
                            }

                            Spacer(minLength: Spacing.s)

                            Text(countdownText(item.until))
                                .font(Typography.caption)
                                .monospacedDigit()
                                .foregroundStyle(Palette.warning)
                        }
                    }
                }
            }
        }
    }

    private func countdownText(_ until: String?) -> String {
        guard let until, Fmt.parse(until) != nil else { return "—" }
        if let left = Fmt.countdown(until: until) {
            return "剩 \(left)"
        }
        return "已恢复"
    }

    // MARK: 最近错误

    private var lastErrorDate: Date? {
        guard let raw = current.lastErr, let date = Fmt.parse(raw) else { return nil }
        // 后端用 0001-01-01 表示"没有错误"
        return date.timeIntervalSince1970 > 0 ? date : nil
    }

    private func errorCard(_ date: Date) -> some View {
        cardChrome {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text("最近错误")
                        .font(Typography.label)
                        .tracking(0.6)
                        .foregroundStyle(Palette.textSecondary)

                    Spacer()

                    Text(Fmt.ago(current.lastErr))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }

                Text(errorDetail(date))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(errorExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .motion(Motion.gentle, value: errorExpanded)

                Button(errorExpanded ? "收起" : "展开") {
                    errorExpanded.toggle()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .buttonStyle(.plain)
                .frame(minWidth: Hit.min, minHeight: Hit.min, alignment: .leading)
            }
        }
    }

    private func errorDetail(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var parts: [String] = [
            "最近一次失败请求发生在 \(formatter.string(from: date))（\(Fmt.ago(current.lastErr))）。"
        ]

        if let fails = current.sessionDeadFails, fails > 0 {
            parts.append("会话失效计数 \(fails) 次，建议执行「复活」重新登录。")
        } else {
            parts.append("会话失效计数 0 次，多为上游限流或单次网络抖动。")
        }

        if let models = current.rateLimitedModels, !models.isEmpty {
            parts.append("当前有 \(models.count) 个模型处于限流状态。")
        }

        if let raw = current.lastErr, !raw.isEmpty {
            parts.append("原始时间戳：\(raw)")
        }

        return parts.joined()
    }

    // MARK: 操作区

    private var actionsCard: some View {
        cardChrome {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("操作")
                    .font(Typography.label)
                    .tracking(0.6)
                    .foregroundStyle(Palette.textSecondary)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Spacing.s),
                        GridItem(.flexible(), spacing: Spacing.s)
                    ],
                    spacing: Spacing.s
                ) {
                    ForEach(AccountCommand.allCases.filter { $0 != .remove }) { command in
                        actionButton(command)
                    }
                }

                Rectangle()
                    .fill(Palette.divider)
                    .frame(height: 1)
                    .padding(.vertical, Spacing.xxs)

                Button {
                    confirmRemove = true
                } label: {
                    Label("移除账号", systemImage: "trash")
                        .font(Typography.callout)
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                .buttonStyle(.bordered)
                .tint(Palette.danger)
                .controlSize(.large)
                .disabled(busy != nil)
                .accessibilityHint("需要二次确认，移除后需重新登录")
            }
        }
    }

    private func actionButton(_ command: AccountCommand) -> some View {
        Button {
            Task { await run(command) }
        } label: {
            if busy == command {
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
        .tint(command.isDestructive ? Palette.danger : Palette.accent)
        .controlSize(.large)
        .disabled(busy != nil)
        .accessibilityHint(command.hint)
    }

    // MARK: 数据与操作

    private func refresh() async {
        guard let client else {
            toast = Toast(kind: .failure, text: "尚未配置服务器地址")
            return
        }
        await loader.load { try await client.status() }
    }

    private func run(_ command: AccountCommand) async {
        guard let client, busy == nil else { return }
        busy = command
        defer { busy = nil }

        do {
            let result = try await client.accountAction(current.uid, action: command.rawValue)
            if let object = result.objectValue, object["ok"]?.boolValue == false {
                let message = object["error"]?.stringValue ?? "服务器拒绝了该操作"
                toast = Toast(kind: .failure, text: "\(command.title)失败：\(message)")
            } else {
                let message = result.objectValue?["message"]?.stringValue ?? ""
                toast = Toast(kind: .success, text: message.isEmpty ? "\(command.title)已提交" : message)
                await loader.load { try await client.status() }
            }
        } catch {
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            toast = Toast(kind: .failure, text: "\(command.title)失败：\(message)")
        }
    }

    private func removeAccount() async {
        guard let client, busy == nil else { return }
        busy = .remove
        defer { busy = nil }

        do {
            let result = try await client.accountAction(current.uid, action: AccountCommand.remove.rawValue)
            if let object = result.objectValue, object["ok"]?.boolValue == false {
                let message = object["error"]?.stringValue ?? "服务器拒绝了该操作"
                toast = Toast(kind: .failure, text: "移除失败：\(message)")
                return
            }
            toast = Toast(kind: .success, text: "已移除 \(current.displayName)")
            try? await Task.sleep(for: .milliseconds(700))
            dismiss()
        } catch {
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            toast = Toast(kind: .failure, text: "移除失败：\(message)")
        }
    }
}

// MARK: - 账号指令

enum AccountCommand: String, CaseIterable, Identifiable {
    case checkin
    case balanceRefresh = "balance"
    case travel
    case compensation
    case pause
    case resume
    case disable
    case revive
    case remove

    var id: String { rawValue }

    var title: String {
        switch self {
        case .checkin: return "签到"
        case .balanceRefresh: return "余额刷新"
        case .travel: return "旅行"
        case .compensation: return "补偿"
        case .pause: return "暂停"
        case .resume: return "恢复"
        case .disable: return "禁用"
        case .revive: return "复活"
        case .remove: return "移除"
        }
    }

    var icon: String {
        switch self {
        case .checkin: return "checkmark.seal"
        case .balanceRefresh: return "arrow.triangle.2.circlepath"
        case .travel: return "airplane"
        case .compensation: return "gift"
        case .pause: return "pause.fill"
        case .resume: return "play.fill"
        case .disable: return "nosign"
        case .revive: return "bolt.heart"
        case .remove: return "trash"
        }
    }

    var isDestructive: Bool {
        self == .remove || self == .disable
    }

    var hint: String {
        switch self {
        case .checkin: return "领取每日签到积分"
        case .balanceRefresh: return "重新拉取该账号的余额"
        case .travel: return "执行一次旅行巡检"
        case .compensation: return "领取礼包或补偿"
        case .pause: return "暂停调度该账号"
        case .resume: return "恢复调度该账号"
        case .disable: return "禁用后不再参与调度"
        case .revive: return "重新登录以刷新失效会话"
        case .remove: return "从账号池中移除"
        }
    }
}

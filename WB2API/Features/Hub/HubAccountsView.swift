import SwiftUI

// MARK: - 脱敏

/// Hub 账号标识脱敏：邮箱打码、手机号（后端已脱敏）保持、UID 隐藏。
enum HubAccountMask {
    /// `calmstrongly@gmail.com` → `cal***@gmail.com`；`185****9797` 原样；其余截断。
    static func name(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "—" }
        if let at = s.firstIndex(of: "@") {
            let local = String(s[..<at])
            let domain = String(s[at...])
            let head = local.count > 3 ? String(local.prefix(3)) : String(local.prefix(1))
            return head + "***" + domain
        }
        if s.contains("*") { return s }
        if s.count <= 4 { return s }
        return String(s.prefix(3)) + "***"
    }
}

// MARK: - 头像

/// Hub 账号头像：与 RN 账号页同款视觉，按 realm 区分国内/国际版 + 右下角状态点。
struct HubAccountAvatar: View {
    let realm: String
    let statusColor: Color
    var size: CGFloat = 42

    private var isGlobal: Bool { realm == "intl" }
    private var tint: Color { isGlobal ? .teal : Accent.primary }
    private var icon: String { isGlobal ? "globe.asia.australia.fill" : "building.2.fill" }

    var body: some View {
        Circle()
            .fill(tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size * 0.62, height: size * 0.62)
            }
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(statusColor)
                    .frame(width: size * 0.30, height: size * 0.30)
                    .overlay {
                        Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2)
                    }
                    .offset(x: 1, y: 1)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - 卡片

/// Hub 账号卡片：头像 + 昵称/状态 + 右侧积分水位，视觉与 RN 账号页一致。
struct HubAccountRow: View {
    let account: JSONValue
    let maskIdentifiers: Bool

    private var uid: String { account.field("uid").stringValue ?? "" }
    private var nickname: String { account.field("nickname").stringValue ?? "" }
    private var realm: String { account.field("realm").stringValue ?? "" }
    private var enabled: Bool { account.field("enabled").boolValue == true }
    private var tokenExpired: Bool { account.field("tokenExpired").boolValue == true }
    private var inCooldown: Bool { account.field("inCooldown").boolValue == true }
    private var remain: Double { account.field("credits").field("remain").finiteNumber ?? 0 }
    private var size: Double { account.field("credits").field("size").finiteNumber ?? 0 }
    private var dailyTokens: Int { account.field("dailyTokensToday").countNumber ?? 0 }

    private var displayName: String {
        let raw = nickname.isEmpty ? (uid.isEmpty ? "—" : String(uid.prefix(8))) : nickname
        return maskIdentifiers ? HubAccountMask.name(raw) : raw
    }

    private var statusColor: Color {
        if !enabled || tokenExpired { return .red }
        if inCooldown { return .orange }
        return .green
    }

    private var statusLine: String {
        if !enabled { return "已停用" }
        if tokenExpired { return "凭证过期" }
        if inCooldown {
            if let s = account.field("cooldownFor").countNumber, s > 0 {
                return "冷却中 · \(secondsText(s)) 后恢复"
            }
            return "冷却中"
        }
        var parts = ["可用"]
        if let raw = lastActivity {
            let ago = Fmt.ago(raw)
            if ago != "—" { parts.append(ago) }
        }
        return parts.joined(separator: " · ")
    }

    private var lastActivity: String? {
        let candidates = [
            account.field("lastActivityReport").stringValue,
            account.field("lastDailyChat").stringValue,
            account.field("lastCheckin").stringValue
        ].compactMap { $0 }
        guard !candidates.isEmpty else { return nil }
        return candidates
            .compactMap { raw -> (Date, String)? in
                guard let d = Fmt.parse(raw) else { return nil }
                return (d, raw)
            }
            .max(by: { $0.0 < $1.0 })?.1
    }

    private func secondsText(_ s: Int) -> String {
        if s < 60 { return "\(s) 秒" }
        if s < 3600 { return "\(s / 60) 分 \(s % 60) 秒" }
        return "\(s / 3600) 小时 \((s % 3600) / 60) 分"
    }

    var body: some View {
        HStack(spacing: Metrics.s + Metrics.xs) {
            HubAccountAvatar(realm: realm, statusColor: statusColor, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle((!enabled || tokenExpired) ? Color.red : Color.secondary)
                    .lineLimit(1)

                Text("今日消耗 \(Fmt.tokens(dailyTokens)) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !maskIdentifiers && !uid.isEmpty {
                    Text(uid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: Metrics.s)

            VStack(alignment: .trailing, spacing: Metrics.xs) {
                Text(HubDashboardFormat.credits(remain))
                    .font(.metricSmall())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                CreditBar(progress: size > 0 ? remain / size : 0)
                    .frame(width: 64)
            }
        }
        .frame(minHeight: Metrics.minTap)
        .contentShape(Rectangle())
        .motion(Motion.numeric, value: remain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName)，\(statusLine)，剩余积分 \(HubDashboardFormat.credits(remain))")
    }
}

// MARK: - 页面

/// DM/Hub 账号页：卡片式列表 + 「隐藏完整账号」脱敏开关（默认开启）。
struct HubAccountsView: View {
    @EnvironmentObject private var session: SessionStore
    let client: HubClient
    @StateObject private var model = HubResourceModel()
    @State private var maskIdentifiers = true
    @State private var query = ""
    @State private var pending: HubPendingAction?

    private var accounts: [JSONValue] { model.document.field("accounts").arrayValue ?? [] }

    /// 国内（cn）在前，国际（intl/gmail）排最后；同域按昵称排序。
    private var sortedAccounts: [JSONValue] {
        accounts.sorted { a, b in
            let rankA = realmRank(a)
            let rankB = realmRank(b)
            if rankA != rankB { return rankA < rankB }
            let na = a.field("nickname").stringValue ?? ""
            let nb = b.field("nickname").stringValue ?? ""
            return na < nb
        }
    }

    private func realmRank(_ account: JSONValue) -> Int {
        account.field("realm").stringValue == "intl" ? 1 : 0
    }

    private var filtered: [JSONValue] {
        let kw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return sortedAccounts }
        return sortedAccounts.filter { account in
            let uid = account.field("uid").stringValue ?? ""
            let nick = account.field("nickname").stringValue ?? ""
            return nick.localizedCaseInsensitiveContains(kw) || uid.localizedCaseInsensitiveContains(kw)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Metrics.s) {
                    maskToggle

                    if let error = model.error {
                        ErrorBanner(message: error, retry: reloadNow)
                    }

                    if model.busy && accounts.isEmpty {
                        LoadingSkeleton(rows: 6)
                    } else if filtered.isEmpty {
                        emptyState
                    } else {
                        updateStamp
                        ForEach(Array(filtered.enumerated()), id: \.offset) { _, account in
                            HubAccountRow(account: account, maskIdentifiers: maskIdentifiers)
                                .padding(Metrics.m - Metrics.xs)
                                .glassInteractive(cornerRadius: Metrics.radiusM)
                                .contextMenu { menu(for: account) }
                        }
                    }
                }
                .padding(.horizontal, Metrics.m)
                .padding(.bottom, Metrics.xl)
            }
            .scrollIndicators(.hidden)
            .background {
                LinearGradient(colors: [Accent.soft.opacity(0.9), Color.clear], startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
            }
            .background(.background)
            .navigationTitle("账号")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索昵称或 UID")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: reloadNow) {
                        if model.busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(model.busy)
                    .accessibilityLabel("刷新账号状态")
                }
            }
            .task { await reload() }
            .refreshable { await reload() }
            .confirmationDialog(
                pending?.title ?? "确认操作",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible
            ) {
                if let action = pending {
                    Button("确认执行") {
                        pending = nil
                        let client = self.client
                        Task {
                            if await model.perform(client: client, path: action.path, body: action.body) {
                                await reload(using: client)
                            }
                        }
                    }
                }
                Button("取消", role: .cancel) { pending = nil }
            } message: {
                Text("仅操作当前服务器「\(session.activeProfile.name)」，不会对 RN 或其他配置执行相同操作。")
            }
        }
    }

    private var maskToggle: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Toggle(isOn: $maskIdentifiers) {
                Label("隐藏完整账号", systemImage: maskIdentifiers ? "eye.slash" : "eye")
            }
            .toggleStyle(.switch)
            .tint(Accent.primary)

            Text(maskIdentifiers ? "邮箱/手机号已打码，UID 不显示" : "正在显示完整账号标识")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .glassCard()
    }

    private var updateStamp: some View {
        HStack(spacing: Metrics.xs) {
            Image(systemName: "clock.arrow.circlepath")
            Text("更新于 \(updateText)")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.top, Metrics.xs)
    }

    private var updateText: String {
        guard let date = model.updated else { return "—" }
        return date.formatted(date: .omitted, time: .standard)
    }

    private var emptyState: some View {
        VStack(spacing: Metrics.m) {
            Image(systemName: "person.2.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(accounts.isEmpty ? "还没有账号" : "没有匹配的账号")
                .font(.headline)
            Text(accounts.isEmpty ? "在网页端接入 WorkBuddy 账号后，下拉刷新即可出现" : "换个关键词试试")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.xl)
    }

    @ViewBuilder
    private func menu(for account: JSONValue) -> some View {
        let uid = account.field("uid").stringValue ?? ""
        let enabled = account.field("enabled").boolValue == true
        Button {
            pending = HubPendingAction(
                title: enabled ? "停用此 Hub 账号？" : "启用此 Hub 账号？",
                path: "accounts/set",
                body: .object(["uid": .string(uid), "enabled": .bool(!enabled)])
            )
        } label: {
            Label(enabled ? "停用此账号" : "启用此账号", systemImage: enabled ? "pause.fill" : "play.fill")
        }
        .disabled(uid.isEmpty)
    }

    private func reloadNow() {
        Task { await reload() }
    }

    private func reload(using client: HubClient? = nil) async {
        await model.load(kind: .accounts, client: client ?? self.client, range: "", uid: "")
    }
}

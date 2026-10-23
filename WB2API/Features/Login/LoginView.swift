import SwiftUI
import UIKit

/// 登录：选区域 → 取登录链接 → 打开浏览器授权 → 每 3 秒轮询结果（最多 5 分钟）。
///
/// 轮询用 `.task(id: pollState)` 驱动：state 变化会取消旧任务并重开，
/// 页面被 pop 时 SwiftUI 自动取消任务，不会留下后台请求。
struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.openURL) private var openURL

    private var client: APIClient? { session.client() }

    /// 接口失败时的兜底区域（与后端 realm 取值一致）。
    private static let fallbackRegions: [LoginRegion] = [
        LoginRegion(key: "cn", label: "国内版"),
        LoginRegion(key: "global", label: "国际版")
    ]

    private static let pollInterval: Duration = .seconds(3)
    private static let pollTimeout: TimeInterval = 300

    @State private var loader = Loader<LoginRegionsResponse>()
    @State private var regions: [LoginRegion] = []
    @State private var realm = "cn"

    @State private var starting = false
    @State private var start: LoginStartResponse?
    @State private var pollState: String?
    @State private var deadline: Date?
    @State private var result: LoginPollResponse?
    @State private var pollNote: String?
    @State private var toast: Toast?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if let error = loader.error {
                    ErrorBanner(message: error) {
                        Task { await loadRegions() }
                    }
                    .padding(.horizontal, -Spacing.m)
                }

                if loader.isLoading && regions.isEmpty {
                    SkeletonRows(count: 3)
                        .padding(.horizontal, -Spacing.m)
                } else {
                    regionCard
                    actionButton

                    if let start {
                        linkCard(start)
                    }
                    if pollState != nil {
                        pollingCard
                    }
                    if let result {
                        successCard(result)
                    }
                    if let pollNote {
                        Text(pollNote)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.warning)
                            .padding(.horizontal, Spacing.xs)
                    }
                }
            }
            .padding(Spacing.m)
        }
        .background(Palette.background)
        .navigationTitle("登录")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadRegions() }
        .task {
            if regions.isEmpty { await loadRegions() }
        }
        .task(id: pollState) {
            guard let state = pollState else { return }
            await pollLoop(state: state)
        }
        .toast($toast)
    }

    // MARK: - 区域

    private var regionCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("登录区域")
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)

            if regions.count > 3 {
                Picker("区域", selection: $realm) {
                    ForEach(regions) { region in
                        Text(region.label ?? region.key ?? "—").tag(region.key ?? "")
                    }
                }
                .pickerStyle(.menu)
                .tint(Palette.accent)
            } else {
                Picker("区域", selection: $realm) {
                    ForEach(regions) { region in
                        Text(region.label ?? region.key ?? "—").tag(region.key ?? "")
                    }
                }
                .pickerStyle(.segmented)
            }

            Text("国内版与国际版账号池互相独立，登录后会自动加入对应池子。")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .motion(Motion.spring, value: realm)
    }

    // MARK: - 主按钮

    private var actionButton: some View {
        Button {
            Task { await beginLogin() }
        } label: {
            HStack(spacing: Spacing.s) {
                if starting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "qrcode")
                }
                Text(start == nil ? "获取登录链接" : "重新获取登录链接")
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
            }
            .padding(Spacing.m)
            .foregroundStyle(Palette.surface)
            .background(Palette.accentGradient, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(client == nil || starting || pollState != nil)
    }

    // MARK: - 链接卡片

    private func linkCard(_ start: LoginStartResponse) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("登录链接")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                if let realm = start.realm {
                    StatusPill(text: realm == "global" ? "国际版" : "国内版", color: Palette.info)
                }
            }

            Text(start.url ?? "服务端未返回链接")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
                .lineLimit(5)
                .padding(Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))

            HStack(spacing: Spacing.s) {
                Button {
                    UIPasteboard.general.string = start.url ?? ""
                    toast = Toast(kind: .success, text: "链接已复制")
                } label: {
                    Label("复制链接", systemImage: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.s)
                }
                .buttonStyle(.bordered)
                .disabled((start.url ?? "").isEmpty)

                Button {
                    openLoginPage(start)
                } label: {
                    Label("打开登录页", systemImage: "safari")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.s)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .disabled(URL(string: start.url ?? "") == nil)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - 轮询中

    private var pollingCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text("等待手机端确认…")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: Spacing.s)
                if let deadline {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(0, Int(deadline.timeIntervalSince(context.date)))
                        Text(String(format: "%d:%02d", left / 60, left % 60))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            Text("每 3 秒检查一次授权结果，5 分钟后自动停止。")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .transition(.opacity)
    }

    // MARK: - 成功卡片

    private func successCard(_ result: LoginPollResponse) -> some View {
        let credits = result.credits
        let total = result.creditsTotal
        let progress: Double = {
            guard let credits, let total, total > 0 else { return 0 }
            return min(max(Double(credits) / Double(total), 0), 1)
        }()

        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.nickname ?? "登录成功")
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(result.uid.map { "UID \(String($0.prefix(8)))" } ?? "已加入账号池")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: Spacing.s)
                if let realm = result.realm {
                    StatusPill(text: realm == "global" ? "国际版" : "国内版", color: Palette.info)
                }
            }

            if credits != nil || total != nil {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text("积分")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Text("\(Fmt.credits(credits)) / \(Fmt.credits(total))")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.textPrimary)
                    }
                    CreditBar(progress: progress)
                }
            }

            if let message = result.checkinMessage, !message.isEmpty {
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            if let balanceError = result.balanceError, !balanceError.isEmpty {
                Text("余额刷新失败：\(balanceError)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.warning)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .strokeBorder(Palette.success.opacity(0.25), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    // MARK: - 动作

    private func loadRegions() async {
        guard let client else { return }
        await loader.load { try await client.loginRegions() }
        let list = loader.value?.regions ?? []
        regions = list.isEmpty ? Self.fallbackRegions : list
        if !regions.contains(where: { $0.key == realm }) {
            realm = regions.first?.key ?? "cn"
        }
    }

    private func beginLogin() async {
        guard let client else {
            toast = Toast(kind: .failure, text: "服务器地址无效，请先在设置里填写")
            return
        }
        starting = true
        defer { starting = false }

        result = nil
        pollNote = nil
        start = nil
        pollState = nil

        do {
            let response = try await client.loginStart(realm: realm)
            guard response.ok != false else {
                toast = Toast(kind: .failure, text: "服务端拒绝了登录请求")
                return
            }
            start = response
            guard let state = response.state, !state.isEmpty else {
                toast = Toast(kind: .failure, text: "未拿到登录状态，请重试")
                return
            }
            deadline = Date().addingTimeInterval(Self.pollTimeout)
            pollState = state
        } catch {
            toast = Toast(kind: .failure, text: message(error))
        }
    }

    /// 3 秒一次轮询，最多 5 分钟；done 为真时收尾并提示。
    private func pollLoop(state: String) async {
        guard let client else { return }
        let limit = deadline ?? Date().addingTimeInterval(Self.pollTimeout)

        while !Task.isCancelled {
            if Date() >= limit {
                pollNote = "已超过 5 分钟，请重新获取登录链接。"
                toast = Toast(kind: .info, text: "登录等待超时")
                pollState = nil
                return
            }

            do {
                let response = try await client.loginPoll(state: state)
                if response.done == true {
                    result = response
                    pollNote = nil
                    toast = Toast(kind: .success, text: "登录成功，账号已加入池子")
                    pollState = nil
                    return
                }
            } catch {
                if let apiError = error as? APIError, case .unauthorized = apiError {
                    pollNote = apiError.errorDescription
                    pollState = nil
                    return
                }
                // 单次网络抖动不终止轮询，只在下方显示提示
                pollNote = "轮询失败：\(message(error))，仍在重试…"
            }

            do {
                try await Task.sleep(for: Self.pollInterval)
            } catch {
                return
            }
        }
    }

    private func openLoginPage(_ start: LoginStartResponse) {
        guard let raw = start.url, let url = URL(string: raw) else {
            toast = Toast(kind: .failure, text: "链接无效")
            return
        }
        openURL(url)
    }

    private func message(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}

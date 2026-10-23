import SwiftUI

/// 登录：选区域 → 生成授权链接 → 每 3 秒轮询结果（5 分钟超时）。
///
/// 轮询用 `.task(id:)` 绑定授权 state：换链接、离开页面都会自动取消旧循环。
struct LoginView: View {
    @Environment(SessionStore.self) private var session

    @State private var regionsLoader = Loader<LoginRegionsResponse>()
    @State private var regionKey = ""
    @State private var startResponse: LoginStartResponse?
    @State private var pollResult: LoginPollResponse?
    @State private var isStarting = false
    @State private var errorText: String?
    @State private var pollNote: String?
    @State private var timedOut = false

    private var regions: [LoginRegion] {
        regionsLoader.value?.regions ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    SectionHeader(title: "选择区域", subtitle: "登录走所选区域的面板接口")

                    if regionsLoader.isLoading && regions.isEmpty {
                        HStack(spacing: Metrics.s) {
                            ProgressView()
                            Text("加载区域…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let error = regionsLoader.error, regions.isEmpty {
                        ErrorBanner(message: error, retry: retryRegions)
                    } else if regions.isEmpty {
                        Label("没有可用区域", systemImage: "globe")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("登录区域", selection: $regionKey) {
                            ForEach(regions) { region in
                                Text(region.label ?? region.key ?? "—")
                                    .tag(region.key ?? "")
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel("登录区域")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                Button(action: start) {
                    Group {
                        if isStarting {
                            ProgressView()
                        } else {
                            Label(
                                startResponse == nil ? "生成授权链接" : "重新生成链接",
                                systemImage: "link.badge.plus"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .frame(minHeight: Metrics.minTap)
                .disabled(regionKey.isEmpty || isStarting)

                if let startResponse, let urlString = startResponse.url, !urlString.isEmpty {
                    LoginLinkCard(realm: startResponse.realm, urlString: urlString)
                }

                if let pollResult {
                    LoginResultCard(result: pollResult)

                    Button("再登一个账号", systemImage: "person.badge.plus", action: reset)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .frame(minHeight: Metrics.minTap)
                } else if startResponse != nil {
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        HStack(spacing: Metrics.s) {
                            Image(systemName: timedOut ? "hourglass.badge.xmark" : "hourglass")
                                .foregroundStyle(timedOut ? Color.orange : Accent.primary)
                                .symbolEffect(.pulse, options: .repeating, isActive: !timedOut)
                            Text(timedOut ? "授权超时" : "等待授权…")
                                .font(.headline)
                        }

                        Text(timedOut
                             ? "已等待 5 分钟仍未完成，请重新生成链接。"
                             : "每 3 秒自动检查一次，5 分钟未完成将超时。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let pollNote {
                            Text(pollNote)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }

                if let errorText {
                    ErrorBanner(message: errorText, retry: start)
                }
            }
            .padding(Metrics.m)
        }
        .background(.background)
        .navigationTitle("登录")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRegions() }
        .task(id: startResponse?.state) { await pollUntilDone() }
        .sensoryFeedback(.success, trigger: pollResult?.uid)
    }

    // MARK: - 区域

    private func loadRegions() async {
        guard let client = session.client() else { return }
        await regionsLoader.load { try await client.loginRegions() }
        if regionKey.isEmpty, let first = regions.first, let key = first.key {
            regionKey = key
        }
    }

    private func retryRegions() {
        regionsLoader.clearError()
        Task { await loadRegions() }
    }

    // MARK: - 发起登录

    private func start() {
        Task { await performStart() }
    }

    private func performStart() async {
        guard let client = session.client(), !regionKey.isEmpty else { return }
        isStarting = true
        errorText = nil
        pollNote = nil
        timedOut = false
        pollResult = nil
        startResponse = nil
        defer { isStarting = false }

        do {
            startResponse = try await client.loginStart(realm: regionKey)
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func reset() {
        startResponse = nil
        pollResult = nil
        errorText = nil
        pollNote = nil
        timedOut = false
    }

    // MARK: - 轮询

    private func pollUntilDone() async {
        guard let state = startResponse?.state, !state.isEmpty, pollResult == nil else { return }
        let deadline = Date.now.addingTimeInterval(300)

        while Date.now < deadline {
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            if Task.isCancelled || pollResult != nil { return }
            await pollOnce(state: state)
            if pollResult != nil { return }
        }

        if !Task.isCancelled {
            timedOut = true
        }
    }

    private func pollOnce(state: String) async {
        guard let client = session.client() else { return }
        do {
            let response = try await client.loginPoll(state: state)
            if response.done == true {
                pollResult = response
                pollNote = nil
                timedOut = false
            }
        } catch {
            // 单次检查失败不终止整个流程，把原因留在状态卡里。
            pollNote = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
    .environment(SessionStore())
}

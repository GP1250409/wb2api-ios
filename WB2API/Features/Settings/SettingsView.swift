import SwiftUI

/// 设置：服务器地址、api_key（Keychain）、连接测试、关于、退出登录。
struct SettingsView: View {
    @Environment(SessionStore.self) private var session

    private var client: APIClient? { session.client() }

    @State private var keyDraft = ""
    @State private var loadedKey = false
    @State private var testing = false
    @State private var toast: Toast?
    @State private var showSignOut = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        @Bindable var session = session

        Form {
            Section {
                TextField("https://workbuddy.example.com", text: $session.baseURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
            } header: {
                Text("服务器")
            } footer: {
                Text("修改后立即生效，下次请求会使用新地址。")
            }

            Section {
                SecureField("api_key", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    saveKey()
                } label: {
                    HStack {
                        Label("保存密钥", systemImage: "key")
                        Spacer()
                        if session.apiKey == keyDraft.trimmingCharacters(in: .whitespacesAndNewlines), !keyDraft.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Palette.success)
                        }
                    }
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines) == session.apiKey)
            } header: {
                Text("访问密钥")
            } footer: {
                Text("密钥只写入本机钥匙串，不随 iCloud 同步，也不会发往第三方。")
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Label("测试连接", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        if testing {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(testing || session.baseURL == nil)
            } header: {
                Text("连接")
            } footer: {
                Text(session.baseURL == nil ? "服务器地址无效，请检查格式。" : "会用当前填写的地址与密钥请求一次概览接口。")
            }

            Section {
                LabeledContent("版本", value: appVersion)
                LabeledContent("构建", value: buildNumber)
                if let url = URL(string: "https://github.com/chenyynx/wb2api-ios") {
                    Link(destination: url) {
                        HStack {
                            Label("GitHub 仓库", systemImage: "link")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .foregroundStyle(Palette.accent)
                }
                LabeledContent("数据来源", value: "WorkBuddy2API")
            } header: {
                Text("关于")
            }

            Section {
                Button(role: .destructive) {
                    showSignOut = true
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("只清除本机保存的 api_key，不会影响服务器上的账号池。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !loadedKey {
                keyDraft = session.apiKey
                loadedKey = true
            }
        }
        .toast($toast)
        .confirmationDialog("退出登录？", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("退出并清除密钥", role: .destructive) {
                session.signOut()
                keyDraft = ""
                toast = Toast(kind: .info, text: "已退出登录")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后需要重新填写 api_key 才能访问面板。")
        }
    }

    // MARK: - 动作

    private func saveKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        session.update(apiKey: trimmed)
        keyDraft = trimmed
        toast = Toast(kind: .success, text: trimmed.isEmpty ? "已清除密钥" : "密钥已保存到钥匙串")
    }

    private func testConnection() async {
        guard let baseURL = session.baseURL else {
            toast = Toast(kind: .failure, text: "服务器地址无效")
            return
        }
        testing = true
        defer { testing = false }

        let probe = APIClient(
            baseURL: baseURL,
            apiKey: keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            let overview = try await probe.overview()
            toast = Toast(kind: .success, text: "连接成功 · 共 \(overview.total) 个账号")
        } catch {
            toast = Toast(
                kind: .failure,
                text: (error as? APIError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}

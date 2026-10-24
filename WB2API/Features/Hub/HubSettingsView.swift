import SwiftUI
import WebKit

struct HubSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showingWeb = false
    @State private var confirmingSignOut = false
    @State private var checking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("当前 Hub 登录") {
                    LabeledContent("名称", value: session.activeProfile.name)
                    LabeledContent("地址", value: session.baseURLString)
                    Text("保存的是此 Hub 的面板会话，不是 RN API Key。面板密码仅用于登录，不保存在本机。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Cloudflare Access") {
                    AccessLoginButton(address: session.baseURLString, probePath: BackendKind.hub.accessProbe)
                }
                Section("诊断") {
                    Button("检查当前 Hub 登录") { Task { await checkLogin() } }
                        .disabled(checking)
                    if checking { ProgressView() }
                    if let message { Text(message).font(.footnote).textSelection(.enabled) }
                }
                Section("其他功能") {
                    NavigationLink("模型列表") { HubResourceView(kind: .models) }
                    Button("完整网页面板") { showingWeb = true }
                    Text("账号导入、代理、定时策略等高级设置仍使用完整网页面板。网页有独立面板登录，必要时再次输入面板密码；不会把原生会话或密码注入网页。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("重新登录当前 Hub", role: .destructive) { confirmingSignOut = true }
                } footer: {
                    Text("只清除当前服务器的本机面板会话。RN 和其他服务器的保存凭据不受影响。")
                }
            }
            .navigationTitle("Hub 设置")
            .confirmationDialog("清除当前 Hub 的本机登录并重新登录？", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("重新登录", role: .destructive) { session.signOut() }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showingWeb) {
                if let base = session.baseURL { HubWebPanel(baseURL: base) }
            }
        }
    }

    private func checkLogin() async {
        guard let client = session.hubClient() else { return }
        checking = true
        defer { checking = false }
        do {
            let result = try await client.request("panel/status")
            message = result.field("authenticated").boolValue == true ? "当前 Hub 面板登录有效" : HubError.sessionExpired.localizedDescription
        } catch { message = error.localizedDescription }
    }
}

private struct HubWebPanel: View {
    @Environment(\.dismiss) private var dismiss
    let baseURL: URL
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(baseURL.host ?? "").font(.caption.monospaced()).padding(8)
                HubPanelBrowser(url: baseURL.appendingPathComponent("dashboard"))
            }
            .navigationTitle("完整 Hub 面板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
    }
}

private struct HubPanelBrowser: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

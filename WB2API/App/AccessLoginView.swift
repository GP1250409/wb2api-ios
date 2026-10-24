import SwiftUI
import WebKit

struct AccessLoginButton: View {
    let address: String
    var probePath = "panel/api/overview"
    var onAuthenticated: () -> Void = {}
    @State private var showingLogin = false
    @State private var verifiedHost: String?

    private var baseURL: URL? {
        let raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = raw.contains("://") ? raw : "https://" + raw
        guard let url = URL(string: text), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { showingLogin = true } label: {
                Label("CF 邮箱验证", systemImage: "lock.shield")
            }
            .disabled(baseURL == nil)
            if let verifiedHost, verifiedHost == baseURL?.host {
                Label("此站点验证已完成，可重新连接", systemImage: "checkmark.shield")
                    .font(.footnote).foregroundStyle(.green)
            } else {
                Text("使用 Cloudflare Access 的 HTTPS 面板，先在此完成邮箱验证码登录。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingLogin) {
            if let baseURL {
                AccessLoginSheet(baseURL: baseURL, probePath: probePath) {
                    verifiedHost = baseURL.host
                    showingLogin = false
                    onAuthenticated()
                }
            }
        }
    }
}

@MainActor
private final class AccessLoginModel: ObservableObject {
    @Published var message = "请在下方完成 CF 邮箱验证。登录完成后，点右上角「完成验证」。"
    @Published var checking = false
    @Published var reloadID = UUID()
    let baseURL: URL
    let probePath: String
    let onAuthenticated: () -> Void

    init(baseURL: URL, probePath: String, onAuthenticated: @escaping () -> Void) {
        self.baseURL = baseURL
        self.probePath = probePath
        self.onAuthenticated = onAuthenticated
    }

    func check(automatic: Bool = false) async {
        guard !checking else { return }
        // A mere WebKit page load is not proof of authentication.
        // Probe the protected API without ever sending the panel API key to WebKit.
        let url = baseURL.appendingPathComponent(probePath)
        let cookie = await AccessCookieBridge.header(for: url)
        if automatic && cookie == nil { return }
        checking = true
        defer { checking = false }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            req.httpShouldHandleCookies = false
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
            let (data, response) = try await URLSession.panel.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.transport("没有收到 HTTP 响应") }
            do {
                try APIClient.validateResponse(http, data: data)
            } catch APIError.unauthorized {
                // A JSON 401 from the origin is expected: the probe omits the panel key.
                guard http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("application/json") == true else { throw APIError.cloudflareAccessRequired }
            }
            // Neither a cookie alone nor an arbitrary HTTP 200 is sufficient.
            guard (200..<300).contains(http.statusCode) || http.statusCode == 401,
                  (try? JSONSerialization.jsonObject(with: data)) != nil else {
                throw APIError.unexpectedHTML
            }
            message = "验证完成"
            onAuthenticated()
        } catch {
            if !automatic {
                message = (error as? APIError)?.errorDescription ?? "验证检查未完成，请检查网络并重试。"
            }
        }
    }

    func clear() async {
        await AccessCookieBridge.clear(for: baseURL.appendingPathComponent(probePath))
        message = "已清除本 App 对此站点保存的 CF 凭据，请重新验证。"
        reloadID = UUID()
    }
}

private struct AccessLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: AccessLoginModel

    init(baseURL: URL, probePath: String, onAuthenticated: @escaping () -> Void) {
        _model = StateObject(wrappedValue: AccessLoginModel(baseURL: baseURL, probePath: probePath, onAuthenticated: onAuthenticated))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(model.baseURL.host ?? "")
                    .font(.footnote.monospaced()).textSelection(.enabled)
                    .padding(.top, 8)
                Text(model.message)
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                AccessWebView(url: model.baseURL.appendingPathComponent(model.probePath)) {
                    Task { await model.check(automatic: true) }
                }
                .id(model.reloadID)
            }
            .navigationTitle("Cloudflare Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await model.check() } } label: {
                        if model.checking { ProgressView() } else { Text("完成验证") }
                    }
                    .disabled(model.checking)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("清除此站 CF 登录", role: .destructive) {
                        Task { await model.clear() }
                    }
                    .disabled(model.checking)
                }
            }
        }
    }
}

private struct AccessWebView: UIViewRepresentable {
    let url: URL
    let onPageFinished: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPageFinished: onPageFinished) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        // No API key, Authorization header, JS injection or cookie extraction via JS.
        web.load(URLRequest(url: url))
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onPageFinished: () -> Void
        init(onPageFinished: @escaping () -> Void) { self.onPageFinished = onPageFinished }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onPageFinished()
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = navigationAction.request.url?.scheme?.lowercased()
            decisionHandler(scheme == "https" || scheme == "about" ? .allow : .cancel)
        }
    }
}

import SwiftUI

/// 首启配置：服务器地址 + 密钥，玻璃卡片式表单。
struct SetupView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var address = SessionStore.defaultBaseURL
    @State private var key = ""
    @State private var isChecking = false
    @State private var error: String?
    @FocusState private var focused: Field?

    private enum Field { case address, key }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.l) {
                    header
                    form
                    AccessLoginButton(address: address, probePath: session.backend.accessProbe) { error = nil }
                    if let error {
                        ErrorBanner(message: error, retry: { Task { await connect() } })
                    }
                    connectButton
                }
                .padding(Metrics.m)
            }
            .background(.background)
            .navigationTitle("连接面板")
            .navigationBarTitleDisplayMode(.inline)
            .task { address = session.baseURLString }
        }
    }

    private var header: some View {
        VStack(spacing: Metrics.s) {
            BrandMark(size: 56)
            Text("WorkBuddy 面板")
                .font(.largeTitle.bold())
            Text(session.backend == .hub ? "使用此 Hub 面板的登录密码（不是 API Key）" : "填入此 Panel 的 API Key")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, Metrics.xl)
    }

    private var form: some View {
        VStack(spacing: Metrics.m) {
            TextField("https://…", text: $address)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .focused($focused, equals: .address)
                .padding(Metrics.m)
                .compatGlassEffect(.regular, in: RoundedRectangle(cornerRadius: Metrics.radiusM))

            SecureField(session.backend == .hub ? "面板登录密码" : "api_key", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .key)
                .padding(Metrics.m)
                .compatGlassEffect(.regular, in: RoundedRectangle(cornerRadius: Metrics.radiusM))
        }
    }

    private var connectButton: some View {
        Button(action: { Task { await connect() } }) {
            if isChecking {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("连接")
                    .bold()
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(address.isEmpty || key.isEmpty || isChecking)
    }

    private func connect() async {
        isChecking = true
        error = nil
        defer { isChecking = false }
        session.baseURLString = address
        guard let base = session.baseURL else {
            error = "服务器地址无效"
            return
        }
        let profileID = session.activeProfileID
        let backend = session.backend
        let revision = session.revision
        do {
            let credential: String
            if backend == .hub {
                // Password is used once for login; only the returned session token is stored.
                credential = try await HubClient(baseURL: base, token: "").login(password: key)
            } else {
                _ = try await APIClient(baseURL: base, apiKey: key).overview()
                credential = key
            }
            guard profileID == session.activeProfileID, backend == session.backend,
                  revision == session.revision, base == session.baseURL else { return }
            let saved = backend == .hub ? session.updateHubToken(credential) : session.update(apiKey: credential)
            if !saved { error = session.credentialError ?? "凭据未能保存" }
            key = ""
        } catch {
            guard profileID == session.activeProfileID else { return }
            self.error = error.localizedDescription
        }
    }
}

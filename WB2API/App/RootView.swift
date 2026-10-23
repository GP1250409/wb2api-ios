import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.isConfigured {
            MainTabs()
        } else {
            SetupView()
        }
    }
}

struct MainTabs: View {
    @State private var selection: Tab = .overview
    @State private var toast: Toast?
    @State private var showSettings = false

    enum Tab: Hashable { case overview, accounts, tasks, data, more }

    var body: some View {
        TabView(selection: $selection) {
            OverviewView()
                .tabItem { Label("概览", systemImage: "gauge.with.dots.needle.50percent") }
                .tag(Tab.overview)

            AccountsView()
                .tabItem { Label("账号", systemImage: "person.2.fill") }
                .tag(Tab.accounts)

            TasksView()
                .tabItem { Label("任务", systemImage: "checklist") }
                .tag(Tab.tasks)

            DataView()
                .tabItem { Label("数据", systemImage: "chart.bar.xaxis") }
                .tag(Tab.data)

            MoreView()
                .tabItem { Label("更多", systemImage: "ellipsis") }
                .tag(Tab.more)
        }
        .toast($toast)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

/// 首次启动：填服务器地址与 api_key。
struct SetupView: View {
    @Environment(SessionStore.self) private var session
    @State private var address: String = SessionStore.defaultBaseURL
    @State private var key: String = ""
    @State private var checking = false
    @State private var error: String?
    @FocusState private var focused: Field?

    private enum Field { case address, key }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Spacing.m) {
                        BrandMark(size: 44)
                        Text("WorkBuddy 面板")
                            .font(Typography.displaySmall)
                            .foregroundStyle(Palette.textPrimary)
                        Text("输入面板地址与访问密钥即可接管账号池")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.l)
                    .listRowBackground(Color.clear)
                }

                Section("服务器") {
                    TextField("https://…", text: $address)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .address)
                }

                Section {
                    SecureField("api_key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .key)
                } header: {
                    Text("访问密钥")
                } footer: {
                    Text("密钥只保存在本机钥匙串，不会上传到任何第三方。")
                }

                if let error {
                    Section {
                        Text(error)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.danger)
                    }
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if checking {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("连接").fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(address.isEmpty || key.isEmpty || checking)
                }
            }
            .navigationTitle("设置")
            .scrollContentBackground(.hidden)
            .background(Palette.background)
        }
    }

    private func connect() async {
        checking = true
        error = nil
        defer { checking = false }
        session.baseURLString = address
        guard let client = session.client() else {
            error = "服务器地址无效"
            return
        }
        let probe = APIClient(baseURL: client.baseURL, apiKey: key)
        do {
            _ = try await probe.overview()
            session.update(apiKey: key)
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

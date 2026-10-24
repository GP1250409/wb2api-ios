import SwiftUI

struct HubMainView: View {
    let client: HubClient
    var body: some View {
        TabView {
            HubOverviewDashboard(client: client)
                .tabItem { Label("概览", systemImage: "speedometer") }
            HubResourceView(client: client, kind: .accounts)
                .tabItem { Label("账号", systemImage: "person.2.fill") }
            HubResourceView(client: client, kind: .tasks)
                .tabItem { Label("任务", systemImage: "checklist") }
            HubUsageDashboard(client: client)
                .tabItem { Label("数据", systemImage: "chart.bar.xaxis") }
            HubSettingsView(client: client)
                .tabItem { Label("更多", systemImage: "ellipsis") }
        }
    }
}

enum HubResourceKind {
    case overview, accounts, tasks, usage, models
    var title: String {
        switch self {
        case .overview: return "Hub 概览"
        case .accounts: return "Hub 账号"
        case .tasks: return "Hub 成长任务"
        case .usage: return "Hub 用量"
        case .models: return "Hub 模型"
        }
    }
}

@MainActor
final class HubResourceModel: ObservableObject {
    @Published var document: JSONValue = .null
    @Published var error: String?
    @Published var busy = false
    @Published var notice: String?
    @Published var updated: Date?
    func load(kind: HubResourceKind, client: HubClient?, range: String, uid: String) async {
        guard let client, !busy else { return }
        busy = true
        defer { busy = false }
        error = nil
        do {
            switch kind {
            case .overview:
                try await client.verifySession()
                document = try await client.request("health")
            case .accounts: document = try await client.accounts()
            case .tasks:
                document = try await client.request("tasks", query: uid.isEmpty ? [] : [URLQueryItem(name: "uid", value: uid)], timeout: 120)
            case .usage:
                document = try await client.request("usage", query: [URLQueryItem(name: "realm", value: "all"), URLQueryItem(name: "range", value: range)])
            case .models: document = try await client.request("v1/models")
            }
            updated = Date()
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }
    func perform(client: HubClient?, path: String, body: JSONValue) async -> Bool {
        guard let client, !busy else { return false }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let result = try await client.perform(path, body: body)
            notice = result.field("msg").stringValue ?? "操作已完成，请查看刷新后的状态。"
            return true
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
            return false
        }
    }
}

struct HubResourceView: View {
    @EnvironmentObject private var session: SessionStore
    let client: HubClient
    let kind: HubResourceKind
    @StateObject private var model = HubResourceModel()
    @State private var range = "today"
    @State private var taskUID = ""
    @State private var pending: HubPendingAction?

    var body: some View {
        NavigationStack {
            List {
                if let error = model.error {
                    Section { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
                if let notice = model.notice {
                    Section { Text(notice).font(.footnote) }
                }
                if model.busy { ProgressView("正在读取当前 Hub…") }
                switch kind {
                case .overview: overviewSections
                case .accounts: accountsSections
                case .tasks: tasksSections
                case .usage: usageSections
                case .models: modelsSections
                }
                if let updated = model.updated {
                    Text("更新于 \(updated.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(kind.title)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(model.busy)
                }
            }
            .task { await reload() }
            .refreshable { await reload() }
            .confirmationDialog(pending?.title ?? "确认操作", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                if let action = pending {
                    Button("确认执行") {
                        pending = nil
                        let client = self.client
                        Task {
                            if await model.perform(client: client, path: action.path, body: action.body) { await reload(using: client) }
                        }
                    }
                }
                Button("取消", role: .cancel) { pending = nil }
            } message: {
                Text("仅操作当前服务器「\(session.activeProfile.name)」，不会对 RN 或其他配置执行相同操作。")
            }
        }
    }

    private func reload(using client: HubClient? = nil) async {
        await model.load(kind: kind, client: client ?? self.client, range: range, uid: taskUID)
    }

    private var overviewSections: some View {
        Section("当前 Hub") {
            LabeledContent("服务器", value: session.activeProfile.name)
            LabeledContent("地址", value: session.baseURLString)
            LabeledContent("运行状态", value: model.document.field("ok").boolValue == true ? "正常" : "未读取")
            HubValueRow(title: "账号总数", value: model.document.field("accounts"))
            HubValueRow(title: "可用账号", value: model.document.field("accounts_ready"))
            HubValueRow(title: "当前出口", value: model.document.field("realm"))
            Text("此页使用 Hub 原生 /health 接口，不套用 RN 的概览数据模型。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct HubPendingAction {
    let title: String
    let path: String
    let body: JSONValue
}

struct HubValueRow: View {
    let title: String
    let value: JSONValue
    var body: some View { LabeledContent(title, value: value.displayText) }
}

private extension HubResourceView {
    @ViewBuilder var accountsSections: some View {
        let accounts = model.document.field("accounts").arrayValue ?? []
        Section("账号（\(accounts.count)）") {
            if accounts.isEmpty && !model.busy { Text("未读取到账号。请刷新或检查当前 Hub 登录状态。") }
            ForEach(Array(accounts.enumerated()), id: \.offset) { item in
                let account = item.element
                let uid = account.field("uid").stringValue ?? ""
                let enabled = account.field("enabled").boolValue == true
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(account.field("nickname").stringValue ?? uid).font(.headline)
                        Spacer()
                        if !uid.isEmpty {
                            Menu {
                                Button(enabled ? "停用此账号" : "启用此账号") {
                                    pending = HubPendingAction(title: enabled ? "停用此 Hub 账号？" : "启用此 Hub 账号？", path: "accounts/set", body: .object(["uid": .string(uid), "enabled": .bool(!enabled)]))
                                }
                            } label: { Image(systemName: "ellipsis.circle") }
                            .disabled(model.busy)
                        }
                    }
                    Text(uid).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Text(enabled ? "已启用" : "已停用")
                        Text(account.field("realm").displayText)
                        if account.field("inCooldown").boolValue == true { Text("冷却中") }
                        if account.field("tokenExpired").boolValue == true { Text("账号凭证过期") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    HubValueRow(title: "剩余积分", value: account.field("credits").field("remain"))
                    HubValueRow(title: "今日 Tokens", value: account.field("dailyTokensToday"))
                }
                .padding(.vertical, 5)
            }
        }
    }

    @ViewBuilder var tasksSections: some View {
        let accounts = model.document.field("accounts").arrayValue ?? []
        Section("任务账号") {
            Picker("查看账号", selection: $taskUID) {
                Text("默认国内账号").tag("")
                ForEach(Array(accounts.enumerated()), id: \.offset) { item in
                    Text(item.element.field("nickname").stringValue ?? "账号")
                        .tag(item.element.field("uid").stringValue ?? "")
                }
            }
            .disabled(model.busy)
            .onChange(of: taskUID) { _ in Task { await reload() } }
            Text(model.document.field("account").field("nickname").stringValue ?? model.document.field("msg").stringValue ?? "")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section("成长状态") {
            HubValueRow(title: "能量", value: model.document.field("summary").field("energy"))
            HubValueRow(title: "连续打卡天数", value: model.document.field("summary").field("streak_days"))
        }
        Section("任务列表") {
            let tasks = model.document.field("tasks").arrayValue ?? []
            if tasks.isEmpty && !model.busy { Text("暂无成长任务，或上游尚未返回任务。") }
            ForEach(Array(tasks.enumerated()), id: \.offset) { item in
                let task = item.element
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.field("name").stringValue ?? task.field("task_code").displayText).font(.headline)
                    Text(task.field("description").stringValue ?? "").font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("状态", value: task.field("status").displayText)
                    LabeledContent("进度", value: task.field("current").displayText + " / " + task.field("target").displayText)
                    HubValueRow(title: "积分奖励", value: task.field("reward_credit"))
                }
                .padding(.vertical, 4)
            }
        }
        Section {
            Button(taskUID.isEmpty ? "执行全部国内账号成长任务…" : "执行所选账号成长任务…") {
                pending = HubPendingAction(title: taskUID.isEmpty ? "对所有参与任务的国内账号执行成长任务并领取奖励？" : "执行所选账号的成长任务并领取奖励？", path: "tasks/run", body: .object(["uid": .string(taskUID.isEmpty ? "all" : taskUID), "claim": .bool(true)]))
            }
            .disabled(model.busy || accounts.isEmpty)
            Text("不会自动执行。只有确认后才提交任务；切换服务器不会撤销服务器已经开始的任务。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder var usageSections: some View {
        Section {
            Picker("统计区间", selection: $range) {
                Text("今天").tag("today")
                Text("本周").tag("week")
                Text("本月").tag("month")
                Text("全部").tag("all")
            }
            .disabled(model.busy)
            .onChange(of: range) { _ in Task { await reload() } }
            Text("今天、本周、本月按服务器本地日历边界统计；所有出口合计。")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("区间汇总") {
            HubValueRow(title: "请求数", value: model.document.field("requests"))
            HubValueRow(title: "错误数", value: model.document.field("errors"))
            HubValueRow(title: "输入 Tokens", value: model.document.field("prompt_tokens"))
            HubValueRow(title: "输出 Tokens", value: model.document.field("completion_tokens"))
            HubValueRow(title: "总 Tokens", value: model.document.field("total_tokens"))
            HubValueRow(title: "积分消耗", value: model.document.field("credit"))
            HubValueRow(title: "估算费用（CNY）", value: model.document.field("cost_cny"))
        }
        Section("按模型") {
            let models = model.document.field("by_model").objectValue ?? [:]
            ForEach(models.keys.sorted(), id: \.self) { name in
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline)
                    HubValueRow(title: "请求数", value: models[name]?.field("requests") ?? .null)
                    HubValueRow(title: "总 Tokens", value: models[name]?.field("total_tokens") ?? .null)
                }
            }
        }
    }

    @ViewBuilder var modelsSections: some View {
        Section("模型") {
            let items = model.document.field("data").arrayValue ?? []
            ForEach(Array(items.enumerated()), id: \.offset) { item in
                VStack(alignment: .leading) {
                    Text(item.element.field("id").displayText).font(.headline).textSelection(.enabled)
                    Text(item.element.field("owned_by").displayText).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

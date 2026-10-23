import SwiftUI

// MARK: - 账号列表

struct AccountsView: View {
    @Environment(SessionStore.self) private var session

    @State private var loader = Loader<StatusResponse>()
    @State private var toast: Toast?
    @State private var query = ""
    @State private var filter: AccountFilter = .all
    @State private var busyUIDs: Set<String> = []
    @State private var setupError: String?

    private var client: APIClient? { session.client() }

    var body: some View {
        NavigationStack {
            List {
                if let message = loader.error ?? setupError {
                    ErrorBanner(message: message) {
                        Task { await refresh() }
                    }
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: Spacing.s, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if loader.value == nil {
                    if loader.error == nil && setupError == nil {
                        SkeletonRows(count: 6)
                            .listRowInsets(EdgeInsets(top: Spacing.m, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else if filtered.isEmpty {
                    emptyState
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(filtered) { account in
                        NavigationLink(value: account) {
                            AccountRow(account: account)
                        }
                        .listRowBackground(Palette.surface)
                        .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.m, bottom: Spacing.xs, trailing: Spacing.m))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Task { await perform(.checkin, on: account) }
                            } label: {
                                Label("签到", systemImage: "checkmark.seal")
                            }
                            .tint(Palette.accent)

                            Button {
                                Task { await perform(.revive, on: account) }
                            } label: {
                                Label("复活", systemImage: "bolt.heart")
                            }
                            .tint(Palette.info)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                Task { await perform(account.isDisabled ? .resume : .pause, on: account) }
                            } label: {
                                Label(
                                    account.isDisabled ? "恢复" : "暂停",
                                    systemImage: account.isDisabled ? "play.fill" : "pause.fill"
                                )
                            }
                            .tint(Palette.warning)

                            if !account.isDisabled {
                                Button {
                                    Task { await perform(.disable, on: account) }
                                } label: {
                                    Label("禁用", systemImage: "nosign")
                                }
                                .tint(Palette.danger)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .motion(Motion.spring, value: filter)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("账号")
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索昵称或 UID"
            )
            .refreshable { await refresh() }
            .task { await refresh() }
            .onAppear { refreshIfStale() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新", systemImage: "arrow.clockwise") {
                        Task { await refresh() }
                    }
                    .disabled(loader.isLoading)
                }
            }
            .navigationDestination(for: Account.self) { account in
                AccountDetailView(account: account)
            }
            .toast($toast)
        }
    }

    // MARK: 筛选

    private var filterMenu: some View {
        Menu {
            ForEach(AccountFilter.allCases) { option in
                Button {
                    filter = option
                } label: {
                    if option == filter {
                        Label(option.title(count: count(for: option)), systemImage: "checkmark")
                    } else {
                        Text(option.title(count: count(for: option)))
                    }
                }
            }
        } label: {
            Label(
                "筛选",
                systemImage: filter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("筛选账号")
    }

    private var emptyState: some View {
        EmptyBox(
            title: isNarrowing ? "没有匹配的账号" : "还没有账号",
            message: isNarrowing
                ? "换个关键词，或把筛选切回「全部」"
                : "在网页端登录 WorkBuddy 账号后，下拉刷新即可出现",
            systemImage: isNarrowing ? "magnifyingglass" : "person.2.slash"
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var isNarrowing: Bool {
        filter != .all || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filtered: [Account] {
        let accounts = loader.value?.accounts ?? []
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return accounts.filter { account in
            guard filter.matches(account) else { return false }
            guard !keyword.isEmpty else { return true }
            return account.displayName.localizedCaseInsensitiveContains(keyword)
                || account.uid.localizedCaseInsensitiveContains(keyword)
        }
    }

    private func count(for option: AccountFilter) -> Int {
        (loader.value?.accounts ?? []).filter(option.matches).count
    }

    // MARK: 数据与操作

    private func refresh() async {
        guard let client else {
            toast = Toast(kind: .failure, text: "尚未配置服务器地址")
            return
        }
        await loader.load { try await client.status() }
    }

    private func refreshIfStale() {
        guard loader.value != nil else { return }
        guard let updated = loader.lastUpdated,
              Date().timeIntervalSince(updated) > 20 else { return }
        Task { await refresh() }
    }

    private func perform(_ command: AccountCommand, on account: Account) async {
        guard let client, !busyUIDs.contains(account.uid) else { return }
        busyUIDs.insert(account.uid)
        defer { _ = busyUIDs.remove(account.uid) }

        do {
            let result = try await client.accountAction(account.uid, action: command.rawValue)
            if let object = result.objectValue, object["ok"]?.boolValue == false {
                let message = object["error"]?.stringValue ?? "服务器拒绝了该操作"
                toast = Toast(kind: .failure, text: "\(command.title)失败：\(message)")
            } else {
                let message = result.objectValue?["message"]?.stringValue ?? ""
                toast = Toast(
                    kind: .success,
                    text: message.isEmpty
                        ? "\(account.displayName) · \(command.title)已提交"
                        : message
                )
                await loader.load { try await client.status() }
            }
        } catch {
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            toast = Toast(kind: .failure, text: "\(command.title)失败：\(message)")
        }
    }
}

// MARK: - 筛选项

private enum AccountFilter: String, CaseIterable, Identifiable {
    case all
    case healthy
    case cooling
    case disabled

    var id: String { rawValue }

    var name: String {
        switch self {
        case .all: return "全部"
        case .healthy: return "可用"
        case .cooling: return "冷却"
        case .disabled: return "禁用"
        }
    }

    var isActive: Bool { self != .all }

    func title(count: Int) -> String {
        "\(name)（\(count)）"
    }

    func matches(_ account: Account) -> Bool {
        switch self {
        case .all: return true
        case .healthy: return account.isHealthy
        case .cooling: return account.isCooling
        case .disabled: return account.isDisabled
        }
    }
}

// MARK: - 列表行

private struct AccountRow: View {
    let account: Account

    private var tint: Color {
        Palette.statusColor(
            healthy: account.isHealthy,
            cooling: account.isCooling,
            disabled: account.isDisabled
        )
    }

    private var icon: String {
        if account.isDisabled { return "pause.circle.fill" }
        if account.isCooling { return "hourglass.circle.fill" }
        return "checkmark.circle.fill"
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26)
                .accessibilityLabel(Fmt.accountState(account))

            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)

                Text("\(account.realmLabel) · \(Fmt.ago(account.lastSuccess))")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.s)

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(Fmt.credits(account.credits))
                    .font(Typography.callout)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.numericText())

                CreditBar(progress: account.creditProgress, tint: tint, height: 3)
                    .frame(width: 60)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
    }
}

// MARK: - 路由值

// Account: Hashable 已在 Core/Models.swift 提供（uid 语义），此处不再重复声明。

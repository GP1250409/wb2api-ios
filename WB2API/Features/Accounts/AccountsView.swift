import SwiftUI

/// 账号 Tab：搜索 + 筛选 + 点按进详情（zoom 转场因玻璃卡掉帧已移除）。
struct AccountsView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = AccountsModel()
    @State private var path = NavigationPath()
    @Namespace private var zoomNamespace
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model

        NavigationStack(path: $path) {
            AccountListSection(
                model: model,
                zoomNamespace: zoomNamespace,
                onReload: { reload() },
                onOpen: { path.append($0) },
                onCommand: { perform($0, on: $1) },
                onResetFilter: { model.filter = .all }
            )
            .searchable(
                text: $model.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索昵称或 UID"
            )
            .refreshable {
                await model.load(using: session.client(), syncBalance: true)
            }
            .navigationDestination(for: Account.self) { account in
                AccountDetailView(account: account)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新", systemImage: "arrow.clockwise", action: reload)
                        .disabled(model.isLoading)
                }
            }
            .animation(Motion.snappy, value: model.filter)
            .toast($model.toast)
            .task { await poll() }
            .onAppear {
                Task { await model.refreshIfStale(after: 3, using: session.client()) }
            }
            .onChange(of: scenePhase) { _, phase in
                // 从后台回来时拉一次（仅轻量读缓存级 overview，不触发上游同步）
                guard phase == .active else { return }
                Task { await model.refreshIfStale(after: 3, using: session.client()) }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(AccountFilter.allCases) { option in
                Button {
                    model.filter = option
                } label: {
                    Label(
                        option.title(count: model.count(for: option)),
                        systemImage: option == model.filter ? "checkmark" : option.symbol
                    )
                }
            }

            if model.filter != .all {
                Divider()
                Button("显示全部", systemImage: "arrow.uturn.backward") {
                    model.filter = .all
                }
            }
        } label: {
            Label(
                "筛选",
                systemImage: model.filter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("筛选账号")
    }

    /// 页面可见时每 20 秒读一次 overview（本地接口 ~1s，不打上游），
    /// 保证冷却/禁用/余额状态不会停在旧值。
    private func poll() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(20))
            } catch {
                return
            }
            // 详情页打开时不刷新列表，避免列表重排和转场抢帧
            guard path.isEmpty else { continue }
            await model.refreshIfStale(after: 10, using: session.client())
        }
    }

    private func reload() {
        Task { await model.load(using: session.client(), syncBalance: true) }
    }

    private func perform(_ command: AccountCommand, on account: Account) {
        Task { await model.perform(command, on: account, using: session.client()) }
    }
}

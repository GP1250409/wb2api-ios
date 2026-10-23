import SwiftUI

/// 账号 Tab：搜索 + 筛选 + 滑动手势 + zoom 转场进详情。
struct AccountsView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = AccountsModel()
    @Namespace private var zoomNamespace

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            AccountListSection(
                model: model,
                zoomNamespace: zoomNamespace,
                onReload: { reload() },
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
                    .navigationTransition(.zoom(sourceID: account.uid, in: zoomNamespace))
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
            .onAppear {
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

    private func reload() {
        Task { await model.load(using: session.client(), syncBalance: true) }
    }

    private func perform(_ command: AccountCommand, on account: Account) {
        Task { await model.perform(command, on: account, using: session.client()) }
    }
}

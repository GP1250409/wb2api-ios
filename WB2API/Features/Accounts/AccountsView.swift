import SwiftUI

/// 账号 Tab：搜索 + 筛选 + 滑动手势 + zoom 转场进详情。
struct AccountsView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = AccountsModel()
    @Namespace private var zoomNamespace

    private let rowInsets = EdgeInsets(
        top: Metrics.xs,
        leading: Metrics.m,
        bottom: Metrics.xs,
        trailing: Metrics.m
    )

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                if let message = model.error {
                    ErrorBanner(message: message) {
                        reload()
                    }
                    .listRowInsets(rowInsets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if model.isLoading && model.accounts.isEmpty {
                    LoadingSkeleton(rows: 6)
                        .listRowInsets(rowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else if model.filtered.isEmpty {
                    AccountsEmptyState(
                        isSearching: model.isSearching,
                        query: model.query,
                        title: model.emptyTitle,
                        systemImage: model.emptyIcon,
                        message: model.emptyMessage,
                        isFiltered: model.filter != .all
                    ) {
                        model.filter = .all
                    }
                } else {
                    ForEach(model.filtered) { account in
                        AccountListRow(
                            account: account,
                            isBusy: model.busyUIDs.contains(account.uid),
                            namespace: zoomNamespace
                        ) { command in
                            perform(command, on: account)
                        }
                        .listRowInsets(rowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background {
                LinearGradient(
                    colors: [Accent.soft.opacity(0.8), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
            }
            .background(.background)
            .navigationTitle("账号")
            .searchable(
                text: $model.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索昵称或 UID"
            )
            .refreshable {
                await model.load(using: session.client())
            }
            .navigationDestination(for: Account.self) { account in
                AccountDetailView(account: account)
                    .navigationTransition(.zoom(sourceID: account.uid, in: zoomNamespace))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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

    private func reload() {
        Task { await model.load(using: session.client()) }
    }

    private func perform(_ command: AccountCommand, on account: Account) {
        Task { await model.perform(command, on: account, using: session.client()) }
    }
}

import SwiftUI

/// 账号列表主体：骨架 / 空态 / 行集合，独立成文件以缩短类型推断时间。
struct AccountListSection: View {
    let model: AccountsModel
    let zoomNamespace: Namespace.ID
    var onReload: () -> Void
    var onCommand: (AccountCommand, Account) -> Void
    var onResetFilter: () -> Void = {}

    private let rowInsets = EdgeInsets(
        top: Metrics.xs,
        leading: Metrics.m,
        bottom: Metrics.xs,
        trailing: Metrics.m
    )

    var body: some View {
        List {
            if let message = model.error {
                ErrorBanner(message: message, retry: onReload)
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
                    onResetFilter()
                }
            } else {
                ForEach(model.filtered) { account in
                    AccountListRow(
                        account: account,
                        isBusy: model.busyUIDs.contains(account.uid),
                        namespace: zoomNamespace
                    ) { command in
                        onCommand(command, account)
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
    }
}

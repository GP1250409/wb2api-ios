import SwiftUI

/// 账号列表主体：骨架 / 空态 / 行集合，独立成文件以缩短类型推断时间。
struct AccountListSection: View {
    let model: AccountsModel
    let zoomNamespace: Namespace.ID
    var onReload: () -> Void
    var onOpen: (Account) -> Void
    var onCommand: (AccountCommand, Account) -> Void
    var onResetFilter: () -> Void = {}

    /// 上下留 0：卡片间距交给 List 的 rowSpacing，和概览「账号池」一致。
    private let rowInsets = EdgeInsets(
        top: 0,
        leading: Metrics.m,
        bottom: 0,
        trailing: Metrics.m
    )

    var body: some View {
        List {
            if let updated = model.lastUpdated {
                HStack(spacing: Metrics.xs) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("更新于 \(updated, format: .dateTime.hour().minute().second())")
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .listRowInsets(EdgeInsets(top: Metrics.xs, leading: Metrics.m, bottom: 0, trailing: Metrics.m))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
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
                        namespace: zoomNamespace,
                        onOpen: { onOpen(account) }
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
        .listRowSpacing(Metrics.s)
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

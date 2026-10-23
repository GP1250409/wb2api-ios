import SwiftUI

/// 礼包：按账号分组的礼包余量（`client.packages()`）。
///
/// 每组 = 一个账号（Section header 显示昵称 + 该账号 remain/size + 水位条），
/// 组内每行 = 一个礼包（name + remain / used / size + 进度条）。
struct PackagesView: View {
    @Environment(SessionStore.self) private var session

    private var client: APIClient? { session.client() }

    @State private var loader = Loader<PackagesResponse>()

    var body: some View {
        Group {
            if let error = loader.error, loader.value == nil {
                ScrollView {
                    ErrorBanner(message: error) {
                        Task { await reload() }
                    }
                    .padding(Spacing.m)
                }
                .background(Palette.background)
            } else if loader.isLoading && loader.value == nil {
                ScrollView {
                    SkeletonRows(count: 5)
                        .padding(.vertical, Spacing.m)
                }
                .background(Palette.background)
            } else if let response = loader.value, !response.accounts.isEmpty {
                list(response.accounts)
            } else {
                ScrollView {
                    EmptyBox(
                        title: "暂无礼包数据",
                        message: "账号接取礼包后会在这里汇总",
                        systemImage: "gift"
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .padding(Spacing.m)
                }
                .background(Palette.background)
            }
        }
        .navigationTitle("礼包")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task {
            if loader.isEmpty { await reload() }
        }
    }

    // MARK: - 分组列表

    private func list(_ accounts: [PackageAccount]) -> some View {
        List {
            ForEach(accounts) { account in
                Section {
                    let packages = account.packages ?? []
                    if packages.isEmpty {
                        Text("该账号暂无礼包")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .listRowBackground(Palette.surface)
                    } else {
                        ForEach(packages) { item in
                            packageRow(item)
                        }
                    }
                } header: {
                    accountHeader(account)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }

    private func accountHeader(_ account: PackageAccount) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(account.nickname ?? shortUID(account.uid))
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s)
                Text("\(Fmt.credits(account.remain)) / \(Fmt.credits(account.size))")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
            // 账号级水位同样取 remain / size：CreditBar 表达的是「还剩多少」
            CreditBar(progress: ratio(account.remain, of: account.size))
        }
        .textCase(nil)
        .padding(.bottom, Spacing.xxs)
    }

    // MARK: - 礼包行

    private func packageRow(_ item: PackageItem) -> some View {
        // 进度条取 used / size：行内是「已用掉多少」，与账号 header 的剩余水位相反，
        // 这样一眼能看出哪个礼包消耗得快；size 缺失时进度为 0。
        let usedRatio = ratio(item.used, of: item.size)

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name ?? "未命名礼包")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s)
                Text("\(Fmt.credits(item.remain)) / \(Fmt.credits(item.size))")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
            }

            CreditBar(progress: usedRatio, height: 3)

            Text("已用 \(Fmt.credits(item.used)) · 剩 \(Fmt.credits(item.remain))")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
        }
        .padding(.vertical, Spacing.xxs)
        .listRowBackground(Palette.surface)
    }

    // MARK: - 工具

    /// part / whole，夹在 0…1。
    private func ratio(_ part: Int?, of whole: Int?) -> Double {
        guard let part, let whole, whole > 0 else { return 0 }
        return min(max(Double(part) / Double(whole), 0), 1)
    }

    private func shortUID(_ uid: String?) -> String {
        guard let uid, !uid.isEmpty else { return "—" }
        return String(uid.prefix(8))
    }

    // MARK: - 动作

    private func reload() async {
        guard let client else { return }
        await loader.load { try await client.packages() }
    }
}

import SwiftUI

/// 礼包：按账号分组的礼包余量（`client.packages()`）。
struct PackagesView: View {
    @Environment(SessionStore.self) private var session

    private var client: APIClient? { session.client() }

    @State private var loader = Loader<PackagesResponse>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if let error = loader.error {
                    ErrorBanner(message: error) {
                        Task { await reload() }
                    }
                    .padding(.horizontal, -Spacing.m)
                }

                if loader.isLoading && loader.value == nil {
                    SkeletonRows(count: 5)
                        .padding(.horizontal, -Spacing.m)
                } else if let response = loader.value {
                    let accounts = response.accounts ?? []
                    if accounts.isEmpty {
                        EmptyBox(
                            title: "暂无礼包数据",
                            message: "账号接取礼包后会在这里汇总",
                            systemImage: "gift"
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(Array(accounts.indices), id: \.self) { index in
                            accountCard(accounts[index])
                                .staggeredAppear(index: index)
                        }
                    }
                } else if loader.error == nil {
                    EmptyBox(title: "暂无礼包数据", systemImage: "tray")
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(Spacing.m)
        }
        .background(Palette.background)
        .navigationTitle("礼包")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task {
            if loader.isEmpty { await reload() }
        }
    }

    // MARK: - 账号卡片

    private func accountCard(_ account: PackageAccount) -> some View {
        let packages = account.packages ?? []

        return VStack(alignment: .leading, spacing: Spacing.s) {
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

            // 账号级水位：remain / size（与礼包行保持同一口径）
            CreditBar(progress: barProgress(remain: account.remain, size: account.size))

            if packages.isEmpty {
                Text("该账号暂无礼包")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.vertical, Spacing.xs)
            } else {
                ForEach(packages) { item in
                    packageRow(item)
                }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    // MARK: - 礼包行

    private func packageRow(_ item: PackageItem) -> some View {
        // 进度条取 used / size：直观展示已用掉多少；
        // size 缺失时退回 remain / size 的互补口径（1 - remain/size）无法计算，则进度为 0。
        let usedRatio = barProgress(remain: item.used, size: item.size)

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name ?? "未命名礼包")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: Spacing.s)

                Text("\(Fmt.credits(item.remain)) 剩 · 已用 \(Fmt.credits(item.used)) / \(Fmt.credits(item.size))")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }

            CreditBar(progress: usedRatio, height: 3)
        }
        .padding(.vertical, Spacing.xxs)
    }

    // MARK: - 工具

    private func barProgress(remain: Int?, size: Int?) -> Double {
        guard let remain, let size, size > 0 else { return 0 }
        return min(max(Double(remain) / Double(size), 0), 1)
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

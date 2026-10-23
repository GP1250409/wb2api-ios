import SwiftUI

/// 补偿：`client.compensation()` 返回自由 JSON，复用通用 JSONValue 卡片；
/// 顶部「全部补偿」触发批量操作 `client.batch("compensation_all")`。
struct CompensationView: View {
    @Environment(SessionStore.self) private var session

    private var client: APIClient? { session.client() }

    @State private var loader = Loader<JSONValue>()
    @State private var toast: Toast?
    @State private var runningAll = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                allButton

                if let error = loader.error {
                    ErrorBanner(message: error) {
                        Task { await reload() }
                    }
                    .padding(.horizontal, -Spacing.m)
                }

                if loader.isLoading && loader.value == nil {
                    SkeletonRows(count: 4)
                        .padding(.horizontal, -Spacing.m)
                } else if let value = loader.value {
                    let items = JSONValueCards.flatten(value)
                    Text("共 \(items.count) 条")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.xs)

                    JSONValueCards(value: value)
                } else if loader.error == nil {
                    EmptyBox(title: "暂无补偿记录", systemImage: "arrow.uturn.backward.circle")
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(Spacing.m)
        }
        .background(Palette.background)
        .navigationTitle("补偿")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task {
            if loader.isEmpty { await reload() }
        }
        .toast($toast)
    }

    // MARK: - 全部补偿

    private var allButton: some View {
        Button {
            Task { await runAll() }
        } label: {
            HStack(spacing: Spacing.s) {
                if runningAll {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.uturn.forward.circle")
                }
                Text("全部补偿")
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
            }
            .padding(Spacing.m)
            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .foregroundStyle(Palette.accentDeep)
        }
        .buttonStyle(.plain)
        .disabled(client == nil || runningAll)
    }

    private func runAll() async {
        guard let client else {
            toast = Toast(kind: .failure, text: "服务器地址无效，请先在设置里填写")
            return
        }
        runningAll = true
        defer { runningAll = false }
        do {
            _ = try await client.batch("compensation_all")
            toast = Toast(kind: .success, text: "已发起全部补偿")
            await reload()
        } catch {
            toast = Toast(
                kind: .failure,
                text: (error as? APIError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private func reload() async {
        guard let client else { return }
        await loader.load { try await client.compensation() }
    }
}

import SwiftUI

/// 积分消耗明细。
struct CreditHistoryView: View {
    @Environment(SessionStore.self) private var session
    @State private var loader = Loader<CreditHistory>()

    private var entries: [CreditEntry] {
        loader.value?.entries ?? []
    }

    private var netChange: Int {
        entries.compactMap(\.delta).reduce(0, +)
    }

    var body: some View {
        List {
            if let error = loader.error {
                Section {
                    ErrorBanner(message: error, retry: retry)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if loader.isLoading && loader.value == nil {
                Section {
                    LoadingSkeleton(rows: 6)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            } else if entries.isEmpty {
                ContentUnavailableView {
                    Label("暂无积分记录", systemImage: "creditcard")
                } description: {
                    Text("产生请求后，这里会显示逐条消耗。")
                }
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(entries) { entry in
                        CreditEntryRow(entry: entry)
                    }
                } header: {
                    Text("最近 \(entries.count) 条")
                } footer: {
                    Text("净变动 \(netChange >= 0 ? "+" : "") \(Fmt.credits(netChange)) · 最多保留 \(loader.value?.limit ?? 0) 条")
                }
            }
        }
        .navigationTitle("积分历史")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(loader.isLoading)
            }
        }
    }

    // MARK: - 动作

    private func load() async {
        guard let client = session.client() else { return }
        await loader.load { try await client.creditHistory(limit: 200) }
    }

    private func refresh() {
        Task { await load() }
    }

    private func retry() {
        loader.clearError()
        Task { await load() }
    }
}

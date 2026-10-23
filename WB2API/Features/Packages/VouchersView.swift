import SwiftUI

/// 券码：展示面板 `school/vouchers` 返回的自由结构。
struct VouchersView: View {
    @Environment(SessionStore.self) private var session
    @State private var loader = Loader<JSONValue>()

    var body: some View {
        JSONRowsView(
            title: "券码",
            value: loader.value,
            error: loader.error,
            isLoading: loader.isLoading,
            emptyTitle: "没有可用券码",
            emptyIcon: "ticket",
            reload: load
        )
        .navigationTitle("券码")
        .navigationBarTitleDisplayMode(.inline)
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
        await loader.load { try await client.vouchers() }
    }

    private func refresh() {
        Task { await load() }
    }
}

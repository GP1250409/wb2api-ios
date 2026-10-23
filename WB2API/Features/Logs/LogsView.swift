import SwiftUI

/// 日志：每 5 秒自动刷新的实时流，按通道筛选，并可进入请求日志与错误汇总。
struct LogsView: View {
    @Environment(SessionStore.self) private var session

    @State private var logs = Loader<LogsResponse>()
    @State private var channel: LogChannel = .all
    @State private var isAutoRefreshEnabled = true

    var body: some View {
        List {
            if let warning = archiveWarning {
                Section {
                    Label(warning, systemImage: "archivebox")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let message = logs.error {
                Section {
                    ErrorBanner(message: message, retry: retry)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            Section {
                LogChannelPicker(selection: $channel)
                    .listRowInsets(EdgeInsets(
                        top: Metrics.s,
                        leading: Metrics.m,
                        bottom: Metrics.s,
                        trailing: Metrics.m
                    ))
            }

            Section {
                if isInitialLoading {
                    LoadingSkeleton(rows: 6)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else if visibleEntries.isEmpty {
                    ContentUnavailableView(
                        "暂无日志",
                        systemImage: "text.alignleft",
                        description: Text("该通道还没有记录")
                    )
                } else {
                    ForEach(visibleEntries.indices, id: \.self) { index in
                        LogRowView(entry: visibleEntries[index])
                    }
                }
            } header: {
                HStack(spacing: Metrics.s) {
                    Text("实时日志")
                    Spacer(minLength: 0)
                    Text(isAutoRefreshEnabled ? "5 秒自动刷新" : "已暂停")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                HStack(spacing: Metrics.s) {
                    Text("共 \(visibleEntries.count) 条")
                    Spacer(minLength: 0)
                    if let lastUpdated = logs.lastUpdated {
                        Text(lastUpdated, format: .dateTime.hour().minute().second())
                    }
                }
                .font(.footnote)
            }
        }
        .navigationTitle("日志")
        .navigationDestination(for: LogsRoute.self) { route in
            LogsRouteView(route: route)
        }
        .refreshable { await refreshLogs() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(autoRefreshTitle, systemImage: autoRefreshIcon, action: toggleAutoRefresh)
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("更多", systemImage: "ellipsis.circle") {
                    NavigationLink("请求日志", value: LogsRoute.requestLogs)
                    NavigationLink("错误汇总", value: LogsRoute.errorSummary)
                    Divider()
                    Button("立即刷新", systemImage: "arrow.clockwise", action: refreshNow)
                }
                .labelStyle(.iconOnly)
            }
        }
        .task(id: isAutoRefreshEnabled) { await autoRefresh() }
    }

    private var isInitialLoading: Bool {
        logs.value == nil && logs.error == nil
    }

    private var archiveWarning: String? {
        guard let text = logs.value?.archiveError, !text.isEmpty else { return nil }
        return text
    }

    /// 最新一条在最上面，符合「实时日志」的阅读顺序。
    private var visibleEntries: [LogEntry] {
        let entries = logs.value?.entries ?? []
        let filtered = channel == .all ? entries : entries.filter { channel.matches($0.ch) }
        return Array(filtered.reversed())
    }

    private var autoRefreshTitle: String {
        isAutoRefreshEnabled ? "暂停自动刷新" : "继续自动刷新"
    }

    private var autoRefreshIcon: String {
        isAutoRefreshEnabled ? "pause.circle" : "play.circle"
    }

    // MARK: - 加载

    private func refreshNow() {
        Task { await refreshLogs() }
    }

    private func retry() {
        Task { await refreshLogs() }
    }

    private func toggleAutoRefresh() {
        isAutoRefreshEnabled.toggle()
    }

    private func refreshLogs() async {
        guard let client = session.client() else { return }
        await logs.load { try await client.logs() }
    }

    /// 5 秒一轮；`.task(id:)` 在暂停或离开页面时取消，恢复时立刻补一次。
    private func autoRefresh() async {
        guard isAutoRefreshEnabled else { return }
        await refreshLogs()
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            await refreshLogs()
        }
    }
}

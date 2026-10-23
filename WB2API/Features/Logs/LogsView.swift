import SwiftUI
import Foundation

/// 日志：按通道过滤的实时日志流（5 秒轮询），并提供请求日志与错误汇总入口。
struct LogsView: View {
    @Environment(SessionStore.self) private var session

    @State private var loader = Loader<LogsResponse>()
    @State private var channel = ""
    @State private var isVisible = true

    private var client: APIClient? { session.client() }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                channelBar

                Rectangle()
                    .fill(Palette.divider)
                    .frame(height: 1)

                logList
            }
            .background(Palette.background)
            .navigationTitle("日志")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        RequestLogsView()
                    } label: {
                        Label("请求日志", systemImage: "list.bullet.rectangle")
                    }

                    NavigationLink {
                        ErrorSummaryView()
                    } label: {
                        Label("错误汇总", systemImage: "exclamationmark.triangle")
                    }
                }
            }
            .refreshable { await refresh() }
            .task { await autoRefresh() }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .onChange(of: channels) { _, newValue in
                if !channel.isEmpty && !newValue.contains(channel) {
                    channel = ""
                }
            }
        }
    }

    // MARK: - 顶部筛选

    private var channelBar: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text("日志流")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                Text("每 5 秒自动刷新")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }

            Spacer(minLength: 0)

            Picker("通道", selection: $channel) {
                Text("全部").tag("")
                ForEach(channels, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .tint(Palette.accent)
            .labelsHidden()
            .accessibilityLabel("通道筛选")
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }

    // MARK: - 列表

    private var logList: some View {
        List {
            if let message = loader.error {
                ErrorBanner(message: message) {
                    Task { await refresh() }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
            }

            if let archiveError = loader.value?.archiveError, !archiveError.isEmpty {
                Text("归档异常：\(archiveError)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.warning)
                    .lineLimit(2)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.m, bottom: 0, trailing: Spacing.m))
                    .listRowSeparator(.hidden)
            }

            if loader.value == nil && loader.isLoading {
                SkeletonRows(count: 8)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            } else if entries.isEmpty {
                EmptyBox(
                    title: channel.isEmpty ? "暂无日志" : "该通道暂无日志",
                    message: "下拉刷新，或切换到其他通道",
                    systemImage: "text.alignleft"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(entries) { entry in
                    logRow(entry)
                        .listRowBackground(Palette.surface)
                        .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.m, bottom: Spacing.xs, trailing: Spacing.m))
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Circle()
                .fill(channelColor(entry.ch))
                .frame(width: 6, height: 6)
                .padding(.top, 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.s) {
                    Text(Fmt.clock(entry.ts))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)

                    if let name = entry.ch, !name.isEmpty {
                        Text(name)
                            .font(Typography.label)
                            .tracking(0.4)
                            .foregroundStyle(channelColor(name))
                    }

                    Spacer(minLength: 0)
                }

                Text(entry.text ?? "—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    // MARK: - 数据

    private var allEntries: [LogEntry] {
        loader.value?.entries ?? []
    }

    /// 出现过的通道，去重后最多 5 个。
    private var channels: [String] {
        var seen: [String] = []
        for entry in allEntries {
            guard let raw = entry.ch else { continue }
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || seen.contains(name) { continue }
            seen.append(name)
            if seen.count >= 5 { break }
        }
        return seen
    }

    private var entries: [LogEntry] {
        guard !channel.isEmpty else { return allEntries }
        return allEntries.filter { $0.ch == channel }
    }

    private func channelColor(_ name: String?) -> Color {
        guard let raw = name else { return Palette.textTertiary }
        let text = raw.lowercased()
        if text.contains("server") { return Palette.success }
        if text.contains("panel") { return Palette.info }
        if text.contains("upstream") { return Palette.warning }
        if text.contains("error") || text.contains("fail") { return Palette.danger }
        return Palette.textTertiary
    }

    private func refresh() async {
        guard let client else { return }
        await loader.load { try await client.logs() }
    }

    /// 5 秒轮询；视图销毁时随 `.task` 一起取消。
    private func autoRefresh() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { break }
            if isVisible {
                await refresh()
            }
        }
    }
}

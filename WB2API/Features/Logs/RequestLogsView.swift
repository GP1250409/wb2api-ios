import SwiftUI
import Foundation

/// 请求日志：请求指标卡 + 最近请求流水（可搜索、可选中复制）。
struct RequestLogsView: View {
    @Environment(SessionStore.self) private var session

    @State private var loader = Loader<JSONValue>()
    @State private var metricsLoader = Loader<RequestMetrics>()
    @State private var query = ""

    private var client: APIClient? { session.client() }

    private struct RequestLine: Identifiable {
        let id: Int
        let text: String
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                metricsSection

                Section {
                    if loader.value == nil && loader.isLoading {
                        SkeletonRows(count: 5)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                    } else if let message = loader.error, loader.value == nil {
                        ErrorBanner(message: message) {
                            Task { await refresh() }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                    } else if filteredLines.isEmpty {
                        EmptyBox(
                            title: query.isEmpty ? "暂无请求日志" : "没有匹配的请求",
                            message: query.isEmpty ? "网关还没有处理过请求" : "换一个关键字试试",
                            systemImage: "doc.text.magnifyingglass"
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredLines) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(6)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Spacing.xxs)
                                .listRowBackground(Palette.surface)
                                .listRowSeparator(.hidden)
                        }
                    }
                } header: {
                    HStack(spacing: Spacing.s) {
                        Text("请求日志")
                        Spacer(minLength: 0)
                        Text("\(filteredLines.count) 条")
                            .monospacedDigit()
                    }
                    .font(Typography.label)
                    .tracking(0.6)
                    .foregroundStyle(Palette.textSecondary)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("请求日志")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索请求内容")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新")
                    .disabled(loader.isLoading || metricsLoader.isLoading)
                }
            }
            .refreshable { await refresh() }
            .task { await refresh() }
        }
    }

    // MARK: - 指标

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: Spacing.s),
            GridItem(.flexible(), spacing: Spacing.s)
        ]
    }

    @ViewBuilder
    private var metricsSection: some View {
        Section {
            if let metrics = metricsLoader.value {
                LazyVGrid(columns: metricColumns, spacing: Spacing.s) {
                    StatTile(
                        label: "完成",
                        value: Fmt.compact(metrics.completed),
                        caption: "请求数"
                    )
                    StatTile(
                        label: "失败",
                        value: Fmt.compact(metrics.failed),
                        tint: (metrics.failed ?? 0) > 0 ? Palette.danger : Palette.textSecondary,
                        caption: "错误数"
                    )
                    StatTile(
                        label: "成功率",
                        value: Fmt.percent(metrics.successRate),
                        tint: Palette.success,
                        caption: "已统计请求"
                    )
                    StatTile(
                        label: "平均耗时",
                        value: Fmt.latency(metrics.avgDurationMs),
                        tint: Palette.info,
                        caption: "单次请求"
                    )
                }
                .padding(.horizontal, Spacing.m)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            } else if let message = metricsLoader.error {
                ErrorBanner(message: message) {
                    Task { await refreshMetrics() }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
            } else {
                SkeletonRows(count: 2)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            }
        } header: {
            Text("请求指标")
                .font(Typography.label)
                .tracking(0.6)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    // MARK: - 数据

    private var lines: [RequestLine] {
        guard let raw = loader.value else { return [] }

        let values: [JSONValue]
        if let array = raw.arrayValue {
            values = array
        } else if let object = raw.objectValue,
                  let array = object["entries"]?.arrayValue
                    ?? object["items"]?.arrayValue
                    ?? object["logs"]?.arrayValue
                    ?? object["rows"]?.arrayValue {
            values = array
        } else if raw == .null {
            values = []
        } else {
            values = [raw]
        }

        return values.enumerated().map { index, value in
            RequestLine(id: index, text: truncate(inlineText(value), limit: 200))
        }
    }

    private var filteredLines: [RequestLine] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return lines }
        return lines.filter { $0.text.localizedCaseInsensitiveContains(keyword) }
    }

    private func refresh() async {
        guard let client else { return }
        await loader.load { try await client.requestLogs(limit: 200) }
        await refreshMetrics()
    }

    private func refreshMetrics() async {
        guard let client else { return }
        await metricsLoader.load { try await client.requestMetrics() }
    }

    // MARK: - 文本处理

    private func inlineText(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "—"
        case .array, .object:
            return compactJSON(value)
        default:
            return value.displayText
        }
    }

    private func compactJSON(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let flag):
            return flag ? "true" : "false"
        case .int(let number):
            return String(number)
        case .double(let number):
            return String(format: "%g", number)
        case .string(let text):
            return text
        case .array(let items):
            return "[" + items.map { compactJSON($0) }.joined(separator: ", ") + "]"
        case .object(let object):
            let parts = object.keys.sorted().map { key in
                key + ": " + compactJSON(object[key] ?? .null)
            }
            return "{" + parts.joined(separator: ", ") + "}"
        }
    }

    private func truncate(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit { return trimmed.isEmpty ? "—" : trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}

import SwiftUI
import Foundation

/// 错误汇总：按严重度排序，点行查看完整样本（可选中复制）。
struct ErrorSummaryView: View {
    @Environment(SessionStore.self) private var session

    @State private var loader = Loader<ErrorSummary>()
    @State private var selected: ErrorRow?

    private var client: APIClient? { session.client() }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                if let message = loader.error {
                    ErrorBanner(message: message) {
                        Task { await refresh() }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                }

                if loader.value == nil && loader.isLoading {
                    SkeletonRows(count: 6)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                } else if rows.isEmpty {
                    EmptyBox(
                        title: "没有错误记录",
                        message: "网关最近一切正常",
                        systemImage: "checkmark.seal"
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(rows) { row in
                            Button {
                                selected = row
                            } label: {
                                errorRow(row)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack(spacing: Spacing.s) {
                            Text("错误分布")
                            Spacer(minLength: 0)
                            Text("\(rows.count) 类")
                                .monospacedDigit()
                        }
                        .font(Typography.label)
                        .tracking(0.6)
                        .foregroundStyle(Palette.textSecondary)
                    } footer: {
                        if let scanned = loader.value?.scanned {
                            Text("扫描 \(Fmt.compact(scanned)) 条记录 · 更新于 \(Fmt.ago(loader.value?.updatedAt))")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("错误汇总")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新")
                    .disabled(loader.isLoading)
                }
            }
            .refreshable { await refresh() }
            .task { await refresh() }
            .sheet(item: $selected) { row in
                ErrorDetailSheet(row: row)
            }
        }
    }

    // MARK: - 数据

    private var rows: [ErrorRow] {
        let raw = loader.value?.rows ?? []
        return raw.sorted { left, right in
            let leftRank = severityRank(left.sev)
            let rightRank = severityRank(right.sev)
            if leftRank != rightRank { return leftRank < rightRank }
            return (left.count ?? 0) > (right.count ?? 0)
        }
    }

    private func refresh() async {
        guard let client else { return }
        await loader.load { try await client.errorSummary() }
    }

    private func severityRank(_ severity: String?) -> Int {
        switch (severity ?? "").lowercased() {
        case "error", "err", "fatal", "critical":
            return 0
        case "warn", "warning":
            return 1
        default:
            return 2
        }
    }

    private func severityColor(_ severity: String?) -> Color {
        switch severityRank(severity) {
        case 0: return Palette.danger
        case 1: return Palette.warning
        default: return Palette.textTertiary
        }
    }

    // MARK: - 行

    private func errorRow(_ row: ErrorRow) -> some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            Circle()
                .fill(severityColor(row.sev))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    Text(row.kind ?? "未知类型")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)

                    Text(row.code ?? "—")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Palette.surfaceAlt,
                            in: RoundedRectangle(cornerRadius: Radius.s - 2, style: .continuous)
                        )
                }

                Text("\(row.account ?? "全局") · \(Fmt.ago(row.last))")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            Text(Fmt.compact(row.count))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(severityColor(row.sev))
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
    }
}

// MARK: - 样本详情

private struct ErrorDetailSheet: View {
    let row: ErrorRow

    @Environment(\.dismiss) private var dismiss

    private var sampleText: String {
        if let full = row.sampleFull, !full.isEmpty { return full }
        if let sample = row.sample, !sample.isEmpty { return sample }
        return "无样本内容"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        KeyValueRow(label: "账号", value: row.account ?? "—")
                        KeyValueRow(label: "类型", value: row.kind ?? "—")
                        KeyValueRow(label: "错误码", value: row.code ?? "—")
                        KeyValueRow(label: "次数", value: Fmt.compact(row.count))
                        KeyValueRow(label: "最近", value: Fmt.ago(row.last))
                        KeyValueRow(label: "级别", value: row.sev ?? "—")
                    }
                    .padding(Spacing.m)
                    .background(
                        Palette.surface,
                        in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    )

                    Text(sampleText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.m)
                        .background(
                            Palette.surfaceAlt,
                            in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                        )
                }
                .padding(Spacing.m)
            }
            .background(Palette.background)
            .navigationTitle("错误详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundStyle(Palette.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

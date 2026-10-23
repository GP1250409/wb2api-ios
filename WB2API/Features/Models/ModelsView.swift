import SwiftUI
import Foundation

/// 模型目录：搜索、默认/繁忙标记、展开查看完整能力字段、探测结果。
struct ModelsView: View {
    @Environment(SessionStore.self) private var session

    @State private var loader = Loader<ModelsResponse>()
    @State private var query = ""
    @State private var expandedID: String?
    @State private var probes: JSONValue?
    @State private var probing = false
    @State private var showProbes = false
    @State private var probeError: String?
    @State private var toast: Toast?

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

                if let message = probeError {
                    ErrorBanner(message: message) {
                        Task { await runProbe() }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                }

                if probes != nil {
                    probesSection
                }

                if loader.value == nil && loader.isLoading {
                    SkeletonRows(count: 6)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                } else if filtered.isEmpty {
                    EmptyBox(
                        title: query.isEmpty ? "暂无模型" : "没有匹配的模型",
                        message: query.isEmpty ? "下拉刷新重试" : "换一个关键字试试",
                        systemImage: "cube.transparent"
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(filtered) { model in
                            modelRow(model)
                        }
                    } header: {
                        Text("\(filtered.count) 个模型")
                            .font(Typography.label)
                            .tracking(0.6)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("模型")
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索模型 id 或名称"
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await runProbe() }
                    } label: {
                        if probing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("探测", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    .disabled(probing || loader.isLoading)
                    .accessibilityLabel("探测模型")
                }
            }
            .refreshable { await refresh() }
            .task { await refresh() }
            .toast($toast)
        }
    }

    // MARK: - 数据

    private var filtered: [ModelInfo] {
        let models = loader.value?.models ?? []
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return models }
        return models.filter { model in
            let id = model.modelId ?? ""
            let name = model.name ?? ""
            return id.localizedCaseInsensitiveContains(keyword)
                || name.localizedCaseInsensitiveContains(keyword)
        }
    }

    private func refresh() async {
        guard let client else { return }
        await loader.load { try await client.models() }
    }

    private func runProbe() async {
        guard let client else { return }
        probing = true
        defer { probing = false }
        do {
            let value = try await client.modelProbes()
            probes = value
            probeError = nil
            showProbes = true
            toast = Toast(kind: .success, text: "探测完成")
        } catch {
            probeError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            toast = Toast(kind: .failure, text: "探测失败")
        }
    }

    // MARK: - 探测结果

    @ViewBuilder
    private var probesSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showProbes) {
                Text(probeText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.xs)
            } label: {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("探测结果")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 0)
                }
            }
            .tint(Palette.accent)
        }
    }

    private var probeText: String {
        guard let probes else { return "—" }
        let text = prettyJSON(probes)
        if text.count > 8000 {
            return String(text.prefix(8000)) + "\n…（已截断）"
        }
        return text
    }

    // MARK: - 行

    private func modelRow(_ model: ModelInfo) -> some View {
        let expanded = expandedID == model.id
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Button {
                withAnimation(Motion.spring) {
                    expandedID = expanded ? nil : model.id
                }
            } label: {
                HStack(alignment: .top, spacing: Spacing.s) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(model.modelId ?? model.name ?? "未知模型")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(modelSubtitle(model))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Spacing.xs)

                    HStack(spacing: Spacing.xs) {
                        if model.isDefault == true {
                            StatusPill(text: "默认", color: Palette.accent, icon: "star.fill")
                        }
                        if let busy = model.busy, !busy.isEmpty {
                            StatusPill(text: "繁忙", color: Palette.warning, icon: "hourglass")
                        }
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .padding(.top, 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                modelDetail(model)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, Spacing.xs)
        .motion(Motion.spring, value: expandedID)
    }

    private func modelSubtitle(_ model: ModelInfo) -> String {
        var parts: [String] = []
        if let credits = model.credits, !credits.isEmpty {
            parts.append("倍率 \(credits)")
        }
        if let context = model.contextLength {
            parts.append("上下文 \(Fmt.compact(context))")
        }
        if let text = model.description, !text.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(trimmed.count > 40 ? String(trimmed.prefix(40)) + "…" : trimmed)
        }
        return parts.isEmpty ? "无描述" : parts.joined(separator: " · ")
    }

    private func modelDetail(_ model: ModelInfo) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Rectangle()
                .fill(Palette.divider)
                .frame(height: 1)
                .padding(.vertical, Spacing.xxs)

            detailRow("支持图片", boolText(model.supportsImages), tint: boolTint(model.supportsImages))
            detailRow("支持推理", boolText(model.supportsReasoning), tint: boolTint(model.supportsReasoning))
            detailRow("工具调用", boolText(model.supportsToolCall), tint: boolTint(model.supportsToolCall))
            detailRow("最大输出", model.maxOutputTokens.map { Fmt.compact($0) } ?? "—")
            detailRow("默认强度", model.defaultEffort ?? "—")
            detailRow("仅推理", boolText(model.onlyReasoning), tint: boolTint(model.onlyReasoning))

            if let text = model.description, !text.isEmpty {
                Text(text)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
                    .padding(.top, Spacing.xxs)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String, tint: Color = Palette.textPrimary) -> some View {
        KeyValueRow(label: label, value: value, tint: tint)
    }

    private func boolText(_ value: Bool?) -> String {
        guard let value else { return "—" }
        return value ? "是" : "否"
    }

    private func boolTint(_ value: Bool?) -> Color {
        guard let value else { return Palette.textTertiary }
        return value ? Palette.success : Palette.textSecondary
    }
}

// MARK: - JSON 美化（仅本文件使用）

private func prettyJSON(_ value: JSONValue, indent: Int = 0) -> String {
    let pad = String(repeating: "  ", count: indent)
    let innerPad = String(repeating: "  ", count: indent + 1)
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
        if items.isEmpty { return "[]" }
        let body = items.map { innerPad + prettyJSON($0, indent: indent + 1) }.joined(separator: ",\n")
        return "[\n" + body + "\n" + pad + "]"
    case .object(let object):
        if object.isEmpty { return "{}" }
        let body = object.keys.sorted().map { key in
            innerPad + key + ": " + prettyJSON(object[key] ?? .null, indent: indent + 1)
        }.joined(separator: ",\n")
        return "{\n" + body + "\n" + pad + "}"
    }
}

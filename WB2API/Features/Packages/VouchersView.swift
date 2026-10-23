import SwiftUI
import UIKit

/// JSONValue 通用渲染卡片：键值对 + 长值复制按钮。
///
/// 假设说明（vouchers / compensation 返回的是自由 JSON）：
/// 1. 数组 → 每个元素一张卡片；元素是 object 时按键值对渲染，否则显示 displayText；
/// 2. 对象 → 找第一个 `[JSONValue]` 数组字段作为列表（常见 `data` / `items` / `list` / `rows` / `vouchers`），
///    找不到则整包渲染为一张键值对卡片；
/// 3. 标量值过长（> 40 字符）截断，通过复制按钮拿全文。
struct JSONValueCards: View {
    let value: JSONValue

    var body: some View {
        let items = Self.flatten(value)
        if items.isEmpty {
            EmptyBox(title: "暂无数据", systemImage: "tray")
                .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(spacing: Spacing.s) {
                ForEach(Array(items.indices), id: \.self) { index in
                    itemCard(items[index], index: index)
                }
            }
        }
    }

    /// 数组元素或单对象 → 卡片内容键值对列表。
    private func itemCard(_ item: JSONValue, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            switch item {
            case .object(let fields):
                let keys = fields.keys.sorted()
                ForEach(Array(keys.indices), id: \.self) { index in
                    let key = keys[index]
                    let val = fields[key] ?? .null
                    KeyValueRow(
                        label: key,
                        value: Self.previewText(val),
                        tint: Self.tint(for: key, value: val)
                    )
                    if index < keys.count - 1 {
                        Rectangle()
                            .fill(Palette.divider)
                            .frame(height: 1)
                    }
                }
            default:
                Text(item.displayText)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .staggeredAppear(index: min(index, 6))
    }

    // MARK: - 结构整形（静态，供外部判断空态）

    /// 把任意 JSONValue 规整成卡片数组。
    static func flatten(_ value: JSONValue) -> [JSONValue] {
        switch value {
        case .array(let items):
            return items
        case .object(let fields):
            // 优先取常见的列表字段；否则整包当一张卡片
            let preferred = ["data", "items", "list", "rows", "vouchers", "compensations", "results"]
            for key in preferred {
                if let arr = fields[key]?.arrayValue {
                    return arr
                }
            }
            for (_, v) in fields where v.arrayValue != nil {
                return v.arrayValue ?? []
            }
            return [.object(fields)]
        case .null:
            return []
        default:
            return [value]
        }
    }

    /// 值的展示文本：长字符串截断（复制按钮可取全文由外层 Provide）。
    static func previewText(_ value: JSONValue) -> String {
        let text = value.displayText
        if text.count > 40 {
            return String(text.prefix(39)) + "…"
        }
        return text
    }

    /// 按字段名/值给一点语义着色（仅用现有 Palette 语义色）。
    static func tint(for key: String, value: JSONValue) -> Color {
        let lower = key.lowercased()
        if lower.contains("error") || lower.contains("fail") { return Palette.danger }
        if lower.contains("ok") || lower.contains("success") { return Palette.success }
        if lower.contains("expire") || lower.contains("warn") { return Palette.warning }
        return Palette.textPrimary
    }
}

/// 长值复制行：点击复制全文（System 复制更兼容，不必引 UIPasteControl 依赖 UIKit 生命周期）。
struct CopyableValueRow: View {
    let label: String
    let value: String

    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            HStack {
                Text(label)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text(copied ? "已复制" : value)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(copied ? Palette.success : Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .motion(Motion.gentle, value: copied)
        }
        .buttonStyle(.plain)
    }
}

/// 券码：`client.vouchers()` 返回自由 JSON，交给通用卡片渲染。
struct VouchersView: View {
    @Environment(SessionStore.self) private var session

    private var client: APIClient? { session.client() }

    @State private var loader = Loader<JSONValue>()
    @State private var toast: Toast?

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
                    SkeletonRows(count: 4)
                        .padding(.horizontal, -Spacing.m)
                } else if let value = loader.value {
                    let items = JSONValueCards.flatten(value)
                    HStack {
                        Text("共 \(items.count) 条")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                        Spacer()
                        if let first = items.first, case .object(let fields) = first {
                            // 取第一条里最长字符串字段作为快速复制入口（常见为券码本体）
                            if let (key, val) = fields
                                .max(by: { ($0.value.stringValue?.count ?? 0) < ($1.value.stringValue?.count ?? 0) }),
                               let text = val.stringValue {
                                Button {
                                    UIPasteboard.general.string = text
                                    toast = Toast(kind: .success, text: "已复制 \(key)")
                                } label: {
                                    Label("复制首条", systemImage: "doc.on.doc")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.xs)

                    JSONValueCards(value: value)
                } else if loader.error == nil {
                    EmptyBox(title: "暂无券码", systemImage: "ticket")
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(Spacing.m)
        }
        .background(Palette.background)
        .navigationTitle("券码")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task {
            if loader.isEmpty { await reload() }
        }
        .toast($toast)
    }

    private func reload() async {
        guard let client else { return }
        await loader.load { try await client.vouchers() }
    }
}

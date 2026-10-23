import SwiftUI
import UIKit

/// JSONValue 通用卡片渲染：vouchers / compensation 这类「后端返回自由 JSON」的页面共用。
///
/// 渲染假设：
/// 1. 数组 → 每个元素一张卡片；元素是 object 时逐键渲染 KeyValueRow，标量则直接显示；
/// 2. 对象 → 优先取 `data` / `items` / `list` / `rows` / `vouchers` / `compensations` / `results`
///    里的第一个数组作为列表；都没有数组时才把整个对象当一张卡片（避免空白页）；
/// 3. 每张卡片带「复制」（UIPasteboard）与「分享」（ShareLink），复制内容为该条目的格式化 JSON；
/// 4. 长字符串（> 40 字）在行内截断，靠复制/分享拿全文。
struct JSONValueCards: View {
    let value: JSONValue
    /// 复制成功回调（由页面弹 Toast）。
    var onCopy: (String) -> Void

    var body: some View {
        let items = Self.flatten(value)
        if items.isEmpty {
            EmptyBox(title: "暂无数据", systemImage: "tray")
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            VStack(spacing: Spacing.s) {
                ForEach(Array(items.indices), id: \.self) { index in
                    itemCard(items[index], index: index)
                }
            }
        }
    }

    // MARK: - 单张卡片

    private func itemCard(_ item: JSONValue, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let title = Self.title(for: item, index: index) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.s)
                    Text("#\(index + 1)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .monospacedDigit()
                }
            }

            switch item {
            case .object(let fields):
                let keys = fields.keys.sorted()
                VStack(spacing: Spacing.xs) {
                    ForEach(Array(keys.indices), id: \.self) { keyIndex in
                        let key = keys[keyIndex]
                        let val = fields[key] ?? .null
                        KeyValueRow(
                            label: key,
                            value: Self.previewText(val),
                            tint: Self.tint(for: key, value: val)
                        )
                        if keyIndex < keys.count - 1 {
                            Rectangle()
                                .fill(Palette.divider)
                                .frame(height: 1)
                        }
                    }
                }
            default:
                Text(item.displayText)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textPrimary)
            }

            Rectangle()
                .fill(Palette.divider)
                .frame(height: 1)

            HStack(spacing: Spacing.l) {
                Button {
                    onCopy(Self.rawText(item))
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)

                ShareLink(item: Self.rawText(item)) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }

                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.accent)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .staggeredAppear(index: min(index, 6))
    }

    // MARK: - 结构整形

    /// 把任意 JSONValue 规整成卡片数组。
    static func flatten(_ value: JSONValue) -> [JSONValue] {
        switch value {
        case .array(let items):
            return items
        case .object(let fields):
            let preferred = ["data", "items", "list", "rows", "vouchers", "compensations", "results"]
            for key in preferred {
                if let array = fields[key]?.arrayValue, !array.isEmpty {
                    return array
                }
            }
            for (_, candidate) in fields {
                if let array = candidate.arrayValue, !array.isEmpty {
                    return array
                }
            }
            return [.object(fields)]
        case .null:
            return []
        default:
            return [value]
        }
    }

    /// 卡片标题：取常见名称字段，取不到则不显示标题。
    static func title(for item: JSONValue, index: Int) -> String? {
        guard case .object(let fields) = item else { return nil }
        let candidates = ["name", "title", "code", "voucher", "coupon", "label", "uid", "id", "key"]
        for key in candidates {
            if let text = fields[key]?.stringValue, !text.isEmpty {
                return text
            }
            if let number = fields[key]?.intValue {
                return String(number)
            }
        }
        return nil
    }

    /// 值的展示文本：长字符串截断（复制可取全文）。
    static func previewText(_ value: JSONValue) -> String {
        switch value {
        case .object(let fields):
            return "\(fields.count) 个字段"
        case .array(let items):
            return "\(items.count) 项"
        default:
            let text = value.displayText
            return text.count > 40 ? String(text.prefix(39)) + "…" : text
        }
    }

    /// 按字段名/值给一点语义着色（只用 Palette 里已有的语义色）。
    static func tint(for key: String, value: JSONValue) -> Color {
        let lower = key.lowercased()
        if lower.contains("error") || lower.contains("fail") { return Palette.danger }
        if lower.contains("expire") || lower.contains("warn") { return Palette.warning }
        if lower.contains("ok") || lower.contains("success") { return Palette.success }
        return Palette.textPrimary
    }

    /// 单条记录的格式化 JSON，用于复制 / 分享。
    static func rawText(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return value.displayText
        }
        return text
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
                    Text("共 \(items.count) 条")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.xs)

                    JSONValueCards(value: value) { text in
                        UIPasteboard.general.string = text
                        toast = Toast(kind: .success, text: "已复制该条 JSON")
                    }
                } else if loader.error == nil {
                    EmptyBox(title: "暂无券码", message: "接取券码后会在这里显示", systemImage: "ticket")
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

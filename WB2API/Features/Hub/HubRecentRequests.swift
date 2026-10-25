import SwiftUI

/// Hub「最近请求」卡片：对齐网页端数据页，固定最近 12 条，随数据页一起刷新。
struct HubRecentRequestsCard: View {
    let document: JSONValue?

    private var rows: [JSONValue] { document?.field("rows").arrayValue ?? [] }
    private var total: Int { document?.field("total").countNumber ?? rows.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            SectionHeader(title: "最近请求", subtitle: "共 \(total) 条记录")
            if rows.isEmpty {
                Label("暂无请求记录", systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HubRecentRequestRow(row: row)
                        if index < rows.count - 1 { Divider() }
                    }
                }
                .glassCard()
            }
        }
    }
}

struct HubRecentRequestRow: View {
    let row: JSONValue

    private var iso: String { row.field("iso").stringValue ?? "" }
    private var model: String { row.field("model").stringValue ?? "—" }
    private var account: String { row.field("account").stringValue ?? row.field("key_name").stringValue ?? "" }
    private var outcome: String { row.field("outcome").stringValue ?? "" }
    private var tokens: Int { row.field("total_tokens").countNumber ?? 0 }
    private var elapsedMs: Double { row.field("elapsed_ms").finiteNumber ?? 0 }

    private var ok: Bool { outcome.isEmpty || outcome == "completed" }

    private var timeText: String {
        guard let t = iso.firstIndex(of: "T"), iso.distance(from: t, to: iso.endIndex) >= 9 else { return "—" }
        return String(iso[iso.index(after: t)...].prefix(8))
    }

    private var accountText: String {
        account.isEmpty ? "—" : String(account.prefix(8))
    }

    var body: some View {
        HStack(spacing: Metrics.s) {
            Text(timeText)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(model).font(.callout).lineLimit(1)
                    if !ok {
                        Text("[\(outcome)]").font(.caption2).foregroundStyle(.red).lineLimit(1)
                    }
                }
                Text(accountText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: Metrics.s)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Fmt.tokens(tokens)) tok")
                    .font(.caption).monospacedDigit()
                Text(String(format: "%.1fs", elapsedMs / 1000))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Metrics.xs)
    }
}

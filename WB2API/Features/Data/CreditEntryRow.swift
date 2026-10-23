import SwiftUI

/// 单条积分消耗。
struct CreditEntryRow: View {
    let entry: CreditEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Label(entry.model ?? "未知模型", systemImage: "cpu")
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: Metrics.xs) {
                    Text(shortUID)
                    Text("·")
                    Text(tokenText)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: Metrics.xs) {
                Text(creditText)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(creditTint)
                    .contentTransition(.numericText())

                if let date {
                    Text(date, format: .dateTime.month().day().hour().minute())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, Metrics.xs)
        .frame(minHeight: Metrics.minTap)
        .accessibilityElement(children: .combine)
    }

    private var shortUID: String {
        guard let uid = entry.uid, !uid.isEmpty else { return "—" }
        return String(uid.prefix(6))
    }

    private var tokenText: String {
        Fmt.compact(entry.tokens) + " tok"
    }

    private var creditText: String {
        guard let credits = entry.credits else { return "—" }
        let prefix = credits > 0 ? "+" : ""
        return prefix + Fmt.creditsDouble(credits)
    }

    private var creditTint: Color {
        guard let credits = entry.credits else { return .secondary }
        if credits > 0 { return .green }
        return .primary
    }

    /// 后端时间戳按秒返回；兼容误传毫秒的情况。
    private var date: Date? {
        guard let ts = entry.ts, ts > 0 else { return nil }
        let seconds = ts > 1_000_000_000_000 ? Double(ts) / 1000 : Double(ts)
        return Date(timeIntervalSince1970: seconds)
    }
}

import SwiftUI

/// 单条实时日志：通道徽标 + 时间 + 等宽正文，可长按选中复制。
struct LogRowView: View {
    let entry: LogEntry

    private let isWarning: Bool

    init(entry: LogEntry) {
        self.entry = entry
        let text = entry.text ?? ""
        isWarning = text.hasPrefix("WARN") || text.hasPrefix("ERR")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(spacing: Metrics.s) {
                Label(
                    LogChannel.title(for: entry.ch),
                    systemImage: LogChannel.systemImage(for: entry.ch)
                )
                .font(.tag)
                .foregroundStyle(LogChannel.tint(for: entry.ch))

                if isWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.tag)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("警告")
                }

                Spacer(minLength: 0)

                Text(Fmt.clock(entry.ts))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(entry.text ?? "")
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, Metrics.xs)
    }
}

import SwiftUI

/// 四个批量操作：玻璃按钮，执行中把图标换成 `ProgressView`。
struct BatchActionsRow: View {
    let running: BatchAction?
    let onRun: (BatchAction) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Metrics.s),
        count: 4
    )

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            SectionHeader(title: "批量操作", subtitle: subtitle)

            LazyVGrid(columns: columns, spacing: Metrics.s) {
                ForEach(BatchAction.allCases) { action in
                    Button {
                        onRun(action)
                    } label: {
                        VStack(spacing: Metrics.xs) {
                            if running == action {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(height: 22)
                            } else {
                                Image(systemName: action.icon)
                                    .font(.title3)
                                    .frame(height: 22)
                                    .symbolEffect(.bounce, value: running)
                            }

                            Text(action.shortTitle)
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .disabled(running != nil)
                    .accessibilityLabel(action.title)
                    .accessibilityHint(action.hint)
                }
            }
        }
    }

    private var subtitle: String {
        guard let running else { return "一次对全部账号生效" }
        return "\(running.title)执行中…"
    }
}

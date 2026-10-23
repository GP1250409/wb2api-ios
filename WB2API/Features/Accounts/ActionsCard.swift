import SwiftUI

/// 操作卡：8 个单号操作 + 底部「移除账号」（二次确认挂在按钮上）。
struct ActionsCard: View {
    let busy: AccountCommand?
    let onAction: (AccountCommand) -> Void
    let onRemove: () -> Void

    @State private var confirmRemove = false

    private let columns = [
        GridItem(.flexible(), spacing: Metrics.s),
        GridItem(.flexible(), spacing: Metrics.s)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text("操作")
                .font(.tag)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: Metrics.s) {
                ForEach(AccountCommand.quickActions) { command in
                    Button {
                        onAction(command)
                    } label: {
                        HStack(spacing: Metrics.xs) {
                            if busy == command {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: command.icon)
                            }

                            Text(command.title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: Metrics.minTap)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .disabled(busy != nil)
                    .accessibilityHint(command.hint)
                }
            }

            Button(role: .destructive) {
                confirmRemove = true
            } label: {
                Label("移除账号", systemImage: "trash")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: Metrics.minTap)
            }
            .buttonStyle(.glass)
            .tint(.red)
            .controlSize(.large)
            .disabled(busy != nil)
            .confirmationDialog("移除账号", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("移除", role: .destructive) {
                    onRemove()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("移除后需要重新登录该账号才能恢复，历史用量记录会保留。")
            }
        }
        .glassCard()
    }
}

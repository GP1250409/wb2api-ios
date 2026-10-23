import SwiftUI

/// 队列操作：执行队列（主）+ 扫描全部（次），执行中内联进度。
struct QueueActionsRow: View {
    let isScanning: Bool
    let isRunning: Bool
    let onScan: () -> Void
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Button(action: onRun) {
                QueueActionLabel(
                    title: isRunning ? "正在执行…" : "执行队列",
                    systemImage: "play.fill",
                    isBusy: isRunning
                )
            }
            .buttonStyle(.glassProminent)
            .tint(Accent.primary)
            .disabled(isScanning || isRunning)

            Button(action: onScan) {
                QueueActionLabel(
                    title: isScanning ? "正在扫描…" : "扫描全部",
                    systemImage: "magnifyingglass",
                    isBusy: isScanning
                )
            }
            .buttonStyle(.glass)
            .disabled(isScanning || isRunning)

            Label("扫描会刷新所有账号的任务；执行会按队列并发拉取。", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, Metrics.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

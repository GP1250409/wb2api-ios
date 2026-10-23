import SwiftUI

/// 扫描结果：按账号分组的任务列表，支持逐项「接受 / 领取」。
struct ScanResultView: View {
    let tasks: [AccountTask]
    var onAction: (AccountTask, TaskAction) -> Void

    @State private var expandedUID: String?

    private var groups: [(uid: String, nickname: String, tasks: [AccountTask])] {
        let dict = Dictionary(grouping: tasks, by: \.uid)
        return dict.keys.sorted().compactMap { uid in
            guard let items = dict[uid], let first = items.first else { return nil }
            return (uid, first.nickname.isEmpty ? String(uid.prefix(8)) : first.nickname, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            SectionHeader(title: "扫描结果", subtitle: "\(tasks.count) 项任务 · 点账号展开")

            if tasks.isEmpty {
                ContentUnavailableView(
                    "没有待办任务",
                    systemImage: "checkmark.seal",
                    description: Text("所有账号的任务都已处理或暂无数据")
                )
                .glassCard()
            } else {
                ForEach(groups, id: \.uid) { group in
                    groupCard(group)
                }
            }
        }
    }

    private func groupCard(_ group: (uid: String, nickname: String, tasks: [AccountTask])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    expandedUID = expandedUID == group.uid ? nil : group.uid
                }
            } label: {
                HStack {
                    Label(group.nickname, systemImage: "person.crop.circle")
                        .font(.callout.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(group.tasks.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: expandedUID == group.uid ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(Metrics.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.nickname)，\(group.tasks.count) 项任务")

            if expandedUID == group.uid {
                VStack(spacing: Metrics.s) {
                    ForEach(group.tasks) { task in
                        TaskRow(task: task) { action in
                            onAction(task, action)
                        }
                    }
                }
                .padding([.horizontal, .bottom], Metrics.m)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassCard(padding: 0, cornerRadius: Metrics.radiusM)
    }
}

// MARK: - 单行

enum TaskAction: String {
    case accept = "接受"
    case claim = "领取"
}

private struct TaskRow: View {
    let task: AccountTask
    var onAction: (TaskAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.title)
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                StatusTag(text: task.statusText, systemImage: "circle.fill", tint: task.statusTint)
            }

            if let progress = task.progressText {
                ProgressView(value: task.target.map { Double(min(task.current ?? 0, $0)) / Double($0) } ?? 0)
                    .tint(Accent.primary)
                Text("进度 \(progress)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if let credit = task.credit, credit > 0 {
                    Label("+\(credit)", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if task.canClaim {
                    Button(TaskAction.claim.rawValue) { onAction(.claim) }
                        .font(.footnote.bold())
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                }
                if task.canAccept {
                    Button(TaskAction.accept.rawValue) { onAction(.accept) }
                        .font(.footnote.bold())
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        }
        .padding(Metrics.s)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Metrics.radiusS))
        .animation(.snappy, value: task.acceptStatus)
    }
}

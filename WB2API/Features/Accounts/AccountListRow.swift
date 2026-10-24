import SwiftUI

/// 账号列表的一行：玻璃底、点按 zoom 转场、四个滑动操作。
struct AccountListRow: View {
    let account: Account
    var isBusy: Bool = false
    let namespace: Namespace.ID
    var onOpen: () -> Void
    let onAction: (AccountCommand) -> Void

    var body: some View {
        // 用 Button 而不是 NavigationLink：List 里的 NavigationLink 会自带 chevron，
        // 和概览「账号池」的卡片样式不一致。点按行为与 zoom 转场保持不变。
        Button(action: onOpen) {
            AccountRowView(account: account, isBusy: isBusy)
                .padding(Metrics.m)
                .glassEffect(
                    .regular.tint(Accent.primary.opacity(0.10)).interactive(),
                    in: .rect(cornerRadius: Metrics.radiusM)
                )
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: account.uid, in: namespace)
        .scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.6)
                .scaleEffect(phase.isIdentity ? 1 : 0.97)
        }
        // ScrollView 没有 swipeActions，操作移到长按菜单（能力不丢）
        .contextMenu {
            Button {
                onAction(.checkin)
            } label: {
                Label("签到", systemImage: "checkmark.seal")
            }

            Button {
                onAction(.revive)
            } label: {
                Label("复活", systemImage: "bolt.heart")
            }

            Button {
                onAction(account.isDisabled ? .resume : .pause)
            } label: {
                Label(
                    account.isDisabled ? "恢复" : "暂停",
                    systemImage: account.isDisabled ? "play.fill" : "pause.fill"
                )
            }

            Divider()

            Button(role: .destructive) {
                onAction(.disable)
            } label: {
                Label("禁用", systemImage: "nosign")
            }
        }
    }
}

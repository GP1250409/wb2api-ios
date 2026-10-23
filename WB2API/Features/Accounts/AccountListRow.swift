import SwiftUI

/// 账号列表的一行：玻璃底、点按 zoom 转场、四个滑动操作。
struct AccountListRow: View {
    let account: Account
    var isBusy: Bool = false
    let namespace: Namespace.ID
    let onAction: (AccountCommand) -> Void

    var body: some View {
        NavigationLink(value: account) {
            AccountRowView(account: account, isBusy: isBusy)
                .padding(Metrics.m - Metrics.xs)
                .glassInteractive(cornerRadius: Metrics.radiusM)
        }
        .matchedTransitionSource(id: account.uid, in: namespace)
        .scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.6)
                .scaleEffect(phase.isIdentity ? 1 : 0.97)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                onAction(.checkin)
            } label: {
                Label("签到", systemImage: "checkmark.seal")
            }
            .tint(Accent.primary)

            Button {
                onAction(.revive)
            } label: {
                Label("复活", systemImage: "bolt.heart")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onAction(account.isDisabled ? .resume : .pause)
            } label: {
                Label(
                    account.isDisabled ? "恢复" : "暂停",
                    systemImage: account.isDisabled ? "play.fill" : "pause.fill"
                )
            }
            .tint(.orange)

            Button(role: .destructive) {
                onAction(.disable)
            } label: {
                Label("禁用", systemImage: "nosign")
            }
        }
    }
}

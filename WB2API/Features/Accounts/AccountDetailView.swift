import SwiftUI

/// 账号详情：概览快照 + 积分 / 用量 / 成本 / 操作。
///
/// 刷新时重新调 `client.overview()`，按 uid 找回同一个账号。
struct AccountDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var model = AccountDetailModel()
    @State private var isLeaving = false

    private let account: Account

    init(account: Account) {
        self.account = account
    }

    var body: some View {
        @Bindable var model = model
        let current = model.current(account)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.m) {
                DetailHeaderCard(account: current)
                    .staggeredAppear(index: 0)

                if let message = model.error {
                    ErrorBanner(message: message) {
                        reload()
                    }
                }

                CreditsCard(account: current)
                    .staggeredAppear(index: 1)

                UsageCard(account: current)
                    .staggeredAppear(index: 2)

                ModelCostCard(account: current)
                    .staggeredAppear(index: 3)

                ActionsCard(
                    busy: model.busy,
                    onAction: perform,
                    onRemove: requestRemove
                )
                .staggeredAppear(index: 4)
            }
            .padding(.horizontal, Metrics.m)
            .padding(.top, Metrics.s)
            .padding(.bottom, Metrics.xl)
        }
        .scrollIndicators(.hidden)
        .background {
            LinearGradient(
                colors: [Accent.soft.opacity(0.8), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .background(.background)
        .opacity(isLeaving ? 0 : 1)
        .scaleEffect(isLeaving ? 0.96 : 1)
        .allowsHitTesting(!isLeaving)
        .refreshable {
            await model.load(using: session.client(), syncBalance: true)
        }
        .navigationTitle(current.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新", systemImage: "arrow.clockwise", action: reload)
                    .disabled(model.isLoading || model.busy != nil)
            }
        }
        .toast($model.toast)
        .task {
            model.remember(account.uid)
            await model.load(using: session.client())
        }
    }

    private func reload() {
        Task { await model.load(using: session.client(), syncBalance: true) }
    }

    private func perform(_ command: AccountCommand) {
        Task {
            await model.perform(command, on: model.current(account), using: session.client())
        }
    }

    private func requestRemove() {
        Task {
            let removed = await model.remove(account, using: session.client())
            guard removed else { return }
            withAnimation(Motion.emphasized) {
                isLeaving = true
            } completion: {
                dismiss()
            }
        }
    }
}

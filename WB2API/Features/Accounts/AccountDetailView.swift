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

                NavigationLink {
                    ModelTogglesView(account: current)
                } label: {
                    HStack(spacing: Metrics.s) {
                        Label("模型开关", systemImage: "switch.2")
                            .font(.callout)
                            .foregroundStyle(.primary)
                        Spacer()
                        if let off = current.modelOff, !off.isEmpty {
                            Text("已关闭 \(off.count) 个")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text("全部开启")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(Metrics.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassCard(padding: 0, cornerRadius: Metrics.radiusM)
                .staggeredAppear(index: 4)

                ActionsCard(
                    busy: model.busy,
                    onAction: perform,
                    onRemove: requestRemove
                )
                .staggeredAppear(index: 5)
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
                Button(action: reload) {
                    if model.isLoading || model.isReloading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("刷新该账号")
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

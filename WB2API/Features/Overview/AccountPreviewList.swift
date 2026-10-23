import SwiftUI

/// 概览里的账号预览：前 5 个账号，玻璃行，点进详情。
struct AccountPreviewList: View {
    let accounts: [Account]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            SectionHeader(title: "账号池", subtitle: subtitle)

            ForEach(accounts) { account in
                NavigationLink(value: account) {
                    AccountRowView(account: account)
                        .padding(Metrics.m - Metrics.xs)
                        .glassInteractive(cornerRadius: Metrics.radiusM)
                }
                .buttonStyle(.plain)
                .scrollTransition(.interactive, axis: .vertical) { content, phase in
                    content
                        .opacity(phase.isIdentity ? 1 : 0.55)
                        .scaleEffect(phase.isIdentity ? 1 : 0.96)
                }
                .accessibilityHint("查看账号详情")
            }
        }
    }

    private var subtitle: String? {
        accounts.isEmpty ? nil : "积分最高的 \(accounts.count) 个"
    }
}

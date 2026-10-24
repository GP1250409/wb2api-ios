import SwiftUI

/// 账号行内容：头像 + 昵称/状态 + 积分水位。
///
/// 只负责内容，玻璃底与内边距交给容器（`List` 行或概览的预览行）。
struct AccountRowView: View {
    let account: Account
    var isBusy: Bool = false

    var body: some View {
        HStack(spacing: Metrics.s + Metrics.xs) {
            AccountAvatar(account: account, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Metrics.s)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在执行操作")
            } else {
                VStack(alignment: .trailing, spacing: Metrics.xs) {
                    Text(Fmt.credits(account.credits))
                        .font(.metricSmall())
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    CreditBar(progress: account.creditProgress)
                        .frame(width: 64)
                }
            }
        }
        .frame(minHeight: Metrics.minTap)
        .contentShape(Rectangle())
        .motion(Motion.numeric, value: account.credits)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var statusLine: String {
        if account.needsLogin {
            return account.isDisabled ? "需重新登录 · 登录态已失效" : "登录态异常 · 建议重新登录"
        }
        if let left = account.coolingLeft {
            return "冷却中 · \(left)后恢复"
        }
        var parts = [AccountStatusStyle.text(for: account), Fmt.ago(account.lastSuccess)]
        if account.checkinDone == false {
            parts.append("未签到")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        "\(account.displayName)，\(AccountStatusStyle.text(for: account))，剩余积分 \(Fmt.credits(account.credits))"
    }
}

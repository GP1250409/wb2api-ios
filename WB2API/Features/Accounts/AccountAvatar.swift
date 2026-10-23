import SwiftUI

/// 账号头像：昵称首字 + 右下角状态点。纯装饰，语义由所在行朗读。
struct AccountAvatar: View {
    let account: Account
    var size: CGFloat = 42

    var body: some View {
        Circle()
            .fill(Accent.soft)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(Accent.primary)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(AccountStatusStyle.tint(for: account))
                    .frame(width: size * 0.3, height: size * 0.3)
                    .overlay {
                        Circle()
                            .stroke(.background, lineWidth: 2)
                    }
                    .offset(x: 1, y: 1)
            }
            .accessibilityHidden(true)
    }

    private var initial: String {
        String(account.displayName.prefix(1)).uppercased()
    }
}

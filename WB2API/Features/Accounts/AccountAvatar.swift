import SwiftUI

/// 账号头像：按域区分两种（国内版 / 国际版）+ 右下角状态点。
///
/// 账号只有国内、国际两类，用首字母头像既没信息量又容易混淆，这里直接给域图标。
struct AccountAvatar: View {
    let account: Account
    var size: CGFloat = 42

    private var isGlobal: Bool { account.realm == "global" }

    private var tint: Color { isGlobal ? .teal : Accent.primary }

    private var icon: String {
        isGlobal ? "globe.asia.australia.fill" : "building.2.fill"
    }

    var body: some View {
        Circle()
            .fill(tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: size * 0.40, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(AccountStatusStyle.tint(for: account))
                    .frame(width: size * 0.30, height: size * 0.30)
                    .overlay {
                        Circle()
                            .stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2)
                    }
                    .offset(x: 1, y: 1)
            }
            .accessibilityHidden(true)
    }
}

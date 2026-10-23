import SwiftUI

/// 账号状态的视觉映射：文字 / 颜色 / 图标只在这里定义一次，
/// 列表行、头像状态点、详情头共用。
enum AccountStatusStyle {
    static func text(for account: Account) -> String {
        if account.isDisabled { return "已禁用" }
        if account.isCooling { return "冷却中" }
        return "可用"
    }

    static func tint(for account: Account) -> Color {
        if account.isDisabled { return .red }
        if account.isCooling { return .orange }
        return .green
    }

    static func icon(for account: Account) -> String {
        if account.isDisabled { return "pause.circle.fill" }
        if account.isCooling { return "hourglass.circle.fill" }
        return "checkmark.circle.fill"
    }
}

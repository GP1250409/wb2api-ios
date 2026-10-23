import SwiftUI

// MARK: - Color helpers

extension Color {
    /// 十六进制初始化，支持 #RRGGBB / RRGGBB。
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        if cleaned.count == 6 {
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
        } else {
            r = 0; g = 0; b = 0
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// 双模式颜色：浅色 / 深色各给一个 hex。
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var value: UInt64 = 0
            Scanner(string: cleaned).scanHexInt64(&value)
            return UIColor(
                red: CGFloat((value & 0xFF0000) >> 16) / 255,
                green: CGFloat((value & 0x00FF00) >> 8) / 255,
                blue: CGFloat(value & 0x0000FF) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Palette（唯一色源，视图禁止裸色值）

enum Palette {
    // 强调（全 App 唯一）
    static let accent = Color(light: "C2542F", dark: "E07A55")
    static let accentSoft = Color(light: "FBEDE6", dark: "3A231B")
    static let accentDeep = Color(light: "9B3F22", dark: "F09070")

    // 中性（暖调）
    static let background = Color(light: "FAF8F4", dark: "14120F")
    static let surface = Color(light: "FFFFFF", dark: "1E1C18")
    static let surfaceAlt = Color(light: "F3F0E9", dark: "262420")
    static let textPrimary = Color(light: "1A1815", dark: "F3EFE7")
    static let textSecondary = Color(light: "6B665C", dark: "9A938A")
    static let textTertiary = Color(light: "9A9488", dark: "6E6960")
    static let divider = Color(light: "E8E2D8", dark: "2E2B25")

    // 语义
    static let success = Color(light: "2F7A46", dark: "4FA36A")
    static let warning = Color(light: "B8860B", dark: "D9A93C")
    static let danger = Color(light: "A62B1F", dark: "D4553F")
    static let info = Color(light: "2F6F8F", dark: "6AA6C4")

    /// 主卡渐变：同色相深浅，禁止跨色相。
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 状态色映射，避免各处 switch 漂移。
    static func statusColor(healthy: Bool, cooling: Bool, disabled: Bool) -> Color {
        if disabled { return danger }
        if cooling { return warning }
        return healthy ? success : textTertiary
    }
}

// MARK: - 间距 / 圆角（8pt 网格）

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum Radius {
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum Hit {
    static let min: CGFloat = 44
}

// MARK: - 字体层级

enum Typography {
    /// 屏幕主标题：New York 衬线
    static let display = Font.system(size: 30, weight: .bold, design: .serif)
    static let displaySmall = Font.system(size: 24, weight: .bold, design: .serif)
    /// 分区标题
    static let title = Font.system(size: 20, weight: .semibold)
    /// 正文
    static let body = Font.system(size: 16, weight: .regular)
    /// 列表主文本
    static let callout = Font.system(size: 15, weight: .medium)
    /// 元信息
    static let caption = Font.system(size: 12, weight: .regular)
    /// 小标签（配合 .tracking(0.6) + 大写）
    static let label = Font.system(size: 11, weight: .semibold)
    /// 大号数字（配合 .monospacedDigit()）
    static let metric = Font.system(size: 34, weight: .bold).monospacedDigit()
    static let metricSmall = Font.system(size: 22, weight: .semibold).monospacedDigit()
}

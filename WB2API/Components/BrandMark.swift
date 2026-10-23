import SwiftUI

/// 品牌字标：两个叠加圆点（与 App 图标同构）。
struct BrandMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(.primary)
                .frame(width: size, height: size)
                .offset(x: -size * 0.18)
            Circle()
                .fill(Accent.primary)
                .frame(width: size * 0.78, height: size * 0.78)
                .offset(x: size * 0.26)
        }
        .accessibilityHidden(true)
    }
}

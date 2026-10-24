import SwiftUI

/// 健康度环：几何形状由 Circle().trim 提供，动画交给系统。
struct RingGauge<Content: View>: View {
    var progress: Double
    var lineWidth: CGFloat = 12
    var tint: LinearGradient = Accent.gradient
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.compatBouncy, value: progress)
            content()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("账号池健康度")
        .accessibilityValue("\(Int(progress * 100))%")
    }
}

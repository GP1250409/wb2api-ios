import SwiftUI

/// 积分水位：系统 ProgressView，自动适配外观。
struct CreditBar: View {
    let progress: Double
    var tint: Color = Accent.primary

    var body: some View {
        ProgressView(value: min(max(progress, 0), 1))
            .progressViewStyle(.linear)
            .tint(tint)
            .animation(.snappy, value: progress)
            .accessibilityLabel("积分水位")
            .accessibilityValue("\(Int(progress * 100))%")
    }
}

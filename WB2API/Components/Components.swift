import SwiftUI

// MARK: - 品牌字标（唯一自绘元素）

struct BrandMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.textPrimary)
                .frame(width: size, height: size)
                .offset(x: -size * 0.18)
            Circle()
                .fill(Palette.accent)
                .frame(width: size * 0.78, height: size * 0.78)
                .offset(x: size * 0.24)
        }
        .accessibilityLabel("WorkBuddy2API")
    }
}

// MARK: - 指标块

struct StatTile: View {
    let label: String
    let value: String
    var tint: Color = Palette.textPrimary
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.label)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Palette.textSecondary)
            Text(value)
                .font(Typography.metricSmall)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption {
                Text(caption)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }
}

// MARK: - 状态标签

struct StatusPill: View {
    let text: String
    let color: Color
    var icon: String?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - 积分水位条

struct CreditBar: View {
    let progress: Double
    var tint: Color = Palette.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.divider)
                Capsule()
                    .fill(tint)
                    .frame(width: max(2, proxy.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(Motion.numeric, value: progress)
        .accessibilityLabel("积分水位")
        .accessibilityValue("\(Int(progress * 100))%")
    }
}

// MARK: - 环形仪表

struct RingGauge<Content: View>: View {
    var progress: Double
    var lineWidth: CGFloat = 10
    var tint: LinearGradient
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.divider, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.emphasized, value: progress)
            content()
        }
    }
}

// MARK: - 分区标题

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.top, Spacing.l)
        .padding(.bottom, Spacing.s)
    }
}

// MARK: - 错误提示条

struct ErrorBanner: View {
    let message: String
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.danger)
            Text(message)
                .font(Typography.caption)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(3)
            Spacer(minLength: 0)
            if let onRetry {
                Button("重试", action: onRetry)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(Spacing.m)
        .background(Palette.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .strokeBorder(Palette.danger.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, Spacing.m)
    }
}

// MARK: - 空状态

struct EmptyBox: View {
    let title: String
    var message: String?
    var systemImage: String = "tray"

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        }
        .foregroundStyle(Palette.textSecondary)
    }
}

// MARK: - 加载骨架

struct SkeletonRows: View {
    var count: Int = 4

    var body: some View {
        VStack(spacing: Spacing.s) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .fill(Palette.surfaceAlt)
                    .frame(height: 56)
                    .redacted(reason: .placeholder)
            }
        }
        .padding(.horizontal, Spacing.m)
    }
}

// MARK: - 轻提示

struct Toast: Equatable, Identifiable {
    enum Kind { case success, failure, info }
    let id = UUID()
    let kind: Kind
    let text: String
}

struct ToastOverlay: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                HStack(spacing: Spacing.s) {
                    Image(systemName: icon(toast.kind))
                        .symbolEffect(.bounce, value: toast.id)
                    Text(toast.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                }
                .foregroundStyle(Palette.surface)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s + 2)
                .background(Palette.textPrimary.opacity(0.92), in: Capsule())
                .padding(.top, Spacing.s)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(2.2))
                    withAnimation(Motion.gentle) { self.toast = nil }
                }
            }
        }
        .animation(Motion.spring, value: toast?.id)
    }

    private func icon(_ kind: Toast.Kind) -> String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }
}

extension View {
    func toast(_ binding: Binding<Toast?>) -> some View {
        modifier(ToastOverlay(toast: binding))
    }
}

// MARK: - 键值行

struct KeyValueRow: View {
    let label: String
    let value: String
    var tint: Color = Palette.textPrimary

    var body: some View {
        HStack {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
    }
}

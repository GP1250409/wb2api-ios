import SwiftUI

// iOS 16 presentation adapters. Deliberately no Symbols/Observation dependency.
struct CompatGlass {
    var color: Color = .clear
    static var regular: Self { Self() }
    func tint(_ color: Color) -> Self { Self(color: color) }
    func interactive() -> Self { self }
}

extension View {
    func compatGlassEffect<S: Shape>(_ glass: CompatGlass, in shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.fill(glass.color).allowsHitTesting(false))
            .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5).allowsHitTesting(false))
    }
}

extension Animation {
    static var compatSnappy: Animation { compatSnappy(duration: 0.35) }
    static func compatSnappy(duration: Double) -> Animation {
        .spring(response: duration, dampingFraction: 0.88)
    }
    static var compatBouncy: Animation { compatBouncy(duration: 0.45) }
    static func compatBouncy(duration: Double) -> Animation {
        .spring(response: duration, dampingFraction: 0.7)
    }
    static var compatSmooth: Animation { compatSmooth(duration: 0.35) }
    static func compatSmooth(duration: Double) -> Animation { .easeInOut(duration: duration) }
}

struct CompatIconButton: View {
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let action: () -> Void
    init(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }
    var body: some View {
        Button(role: role, action: action) { Label(title, systemImage: systemImage) }
    }
}

struct CompatEmptyState: View {
    private let label: AnyView
    private let message: AnyView
    private let actions: AnyView

    init(_ title: String, systemImage: String, description: Text? = nil) {
        label = AnyView(Label(title, systemImage: systemImage))
        message = AnyView(description)
        actions = AnyView(EmptyView())
    }
    init<L: View, D: View>(@ViewBuilder label: () -> L, @ViewBuilder description: () -> D) {
        self.label = AnyView(label())
        self.message = AnyView(description())
        self.actions = AnyView(EmptyView())
    }
    init<L: View, D: View, A: View>(@ViewBuilder label: () -> L, @ViewBuilder description: () -> D, @ViewBuilder actions: () -> A) {
        self.label = AnyView(label())
        self.message = AnyView(description())
        self.actions = AnyView(actions())
    }
    static var search: Self { Self("没有搜索结果", systemImage: "magnifyingglass", description: Text("请尝试其他关键词")) }
    static func search(text: String) -> Self {
        Self("没有搜索结果", systemImage: "magnifyingglass", description: Text("没有与“\(text)”匹配的结果"))
    }
    var body: some View {
        VStack(spacing: 12) {
            label.font(.title3.weight(.semibold))
            message.font(.subheadline).foregroundStyle(.secondary)
            actions
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }
}

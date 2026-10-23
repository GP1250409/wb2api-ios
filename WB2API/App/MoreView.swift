import SwiftUI

/// 「更多」Tab 入口：品牌头 + 全部二级功能入口。
///
/// 统一用 `NavigationLink { Destination() } label: { Label(...) }` 形式，
/// 由本页的 NavigationStack 承载，不依赖外部导航状态。
struct MoreView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Spacing.m) {
                        BrandMark(size: 40)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("WorkBuddy 面板")
                                .font(Typography.title)
                                .foregroundStyle(Palette.textPrimary)
                            Text("v\(appVersion) · 私有部署")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Spacing.s)
                }
                .listRowBackground(Palette.surface)

                Section {
                    NavigationLink {
                        ModelsView()
                    } label: {
                        Label("模型", systemImage: "square.stack.3d.up")
                    }
                    .listRowBackground(Palette.surface)

                    NavigationLink {
                        LogsView()
                    } label: {
                        Label("日志", systemImage: "text.alignleft")
                    }
                    .listRowBackground(Palette.surface)
                } header: {
                    Text("模型与日志")
                }

                Section {
                    NavigationLink {
                        PackagesView()
                    } label: {
                        Label("礼包", systemImage: "gift")
                    }
                    .listRowBackground(Palette.surface)

                    NavigationLink {
                        VouchersView()
                    } label: {
                        Label("券码", systemImage: "ticket")
                    }
                    .listRowBackground(Palette.surface)

                    NavigationLink {
                        CompensationView()
                    } label: {
                        Label("补偿", systemImage: "arrow.uturn.backward.circle")
                    }
                    .listRowBackground(Palette.surface)
                } header: {
                    Text("资源")
                }

                Section {
                    NavigationLink {
                        ConfigView()
                    } label: {
                        Label("配置", systemImage: "slider.horizontal.3")
                    }
                    .listRowBackground(Palette.surface)

                    NavigationLink {
                        LoginView()
                    } label: {
                        Label("登录", systemImage: "person.badge.key")
                    }
                    .listRowBackground(Palette.surface)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    .listRowBackground(Palette.surface)
                } header: {
                    Text("系统")
                } footer: {
                    Text("WorkBuddy2API · 账号池运维面板")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("更多")
        }
    }
}

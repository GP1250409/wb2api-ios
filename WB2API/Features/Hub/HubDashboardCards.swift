import SwiftUI

struct HubDashboardSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.m, content: content)
                .padding(.horizontal, Metrics.m)
                .padding(.top, Metrics.s)
                .padding(.bottom, Metrics.xl)
        }
        .scrollIndicators(.hidden)
        .background {
            LinearGradient(colors: [Accent.soft.opacity(0.8), Color.clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
        .background(.background)
        .tint(Accent.primary)
    }
}

struct HubDashboardHeading: View {
    let title: String
    var subtitle: String?
    var updated: Date?
    var isLoading = false
    var reload: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(spacing: Metrics.s) {
                Text(title).font(.largeTitle.bold())
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button(action: reload) { Image(systemName: "arrow.clockwise") }
                    .disabled(isLoading).accessibilityLabel("刷新当前仪表盘")
                BrandMark(size: 26)
            }
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            if let updated {
                Label("更新于 \(updated.formatted(date: .omitted, time: .standard))", systemImage: "clock")
                    .font(.footnote).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HubHealthSummaryCard: View {
    let data: HubOverviewPresentation?
    private var healthLabel: String { (data?.ready.map(String.init) ?? "—") + "/" + (data?.total.map(String.init) ?? "—") }
    var body: some View {
        HStack(alignment: .center, spacing: Metrics.m) {
            RingGauge(progress: data?.ratio ?? 0, lineWidth: 11) {
                VStack(spacing: 0) {
                    Text(healthLabel).font(.metric(.title2)).lineLimit(1).minimumScaleFactor(0.55)
                    Text("可用").font(.tag).foregroundStyle(.secondary)
                }
                .padding(Metrics.m)
            }
            .frame(width: 122, height: 122)
            .accessibilityLabel("Hub 账号池可用比例")
            .accessibilityValue(data?.ratio.map { Fmt.percent($0) } ?? "未提供")
            VStack(alignment: .leading, spacing: Metrics.s) {
                Text(data?.headline ?? "正在读取账号池…")
                    .font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                if let count = data?.paused, count > 0 { status("person.crop.circle.badge.minus", "\(count) 个账号已停用", .orange) }
                if let count = data?.expired, count > 0 { status("person.badge.key", "\(count) 个账号凭证过期", .red) }
                if let count = data?.cooling, count > 0 { status("hourglass", "\(count) 个账号冷却中", .orange) }
                if let latency = data?.today?.averageLatency {
                    status("speedometer", "今日平均延迟 \(Fmt.latency(latency))", .secondary)
                }
                if let expiry = data?.expiryText { status("hourglass", expiry, .secondary) }
                if data?.accounts == nil { status("info.circle", "账号详情尚未提供", .secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard()
    }
    private func status(_ icon: String, _ text: String, _ color: Color) -> some View {
        Label(text, systemImage: icon).font(.footnote).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct HubOverviewStatsGrid: View {
    let data: HubOverviewPresentation?
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Metrics.s), GridItem(.flexible(), spacing: Metrics.s)], spacing: Metrics.s) {
            StatTile(title: "剩余积分", value: HubDashboardFormat.credits(data?.credits), caption: data?.creditCaption ?? "未提供", tint: Accent.primary)
            StatTile(title: "今日消耗", value: Fmt.tokens(data?.today?.totals.totalTokens), caption: "tokens · 服务器当地今日")
            StatTile(title: "成功率", value: Fmt.percent(data?.today?.successRate), caption: "今日成功 /（成功＋错误）")
            StatTile(title: "缓存命中", value: Fmt.rate(data?.today?.cacheRate), caption: "今日命中 / 输入 Token")
        }
    }
}

struct HubCooldownsCard: View {
    let cooldowns: [HubModelCooldown]?
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            SectionHeader(title: "模型锁池", subtitle: "Hub 账号上报的模型冷却，不等于完整模型可用性")
            if let cooldowns, !cooldowns.isEmpty {
                ForEach(cooldowns) { item in
                    VStack(alignment: .leading, spacing: Metrics.xs) {
                        HStack {
                            Text(item.model).font(.callout.bold()).lineLimit(1).minimumScaleFactor(0.8)
                            Text(item.realmLabel).font(.caption2)
                            Spacer()
                            StatusTag(text: "模型冷却", systemImage: "lock.fill", tint: .orange)
                        }
                        Label("\(item.affected) 个账号受影响 · 最早 \(item.earliest.formatted(date: .omitted, time: .shortened)) 恢复", systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(Metrics.s)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Metrics.radiusS))
                }
            } else {
                Label(cooldowns == nil ? "后端未提供模型冷却明细" : "未返回当前有效的模型冷却记录", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).glassCard()
            }
        }
    }
}

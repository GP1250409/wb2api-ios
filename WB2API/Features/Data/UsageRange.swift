import SwiftUI

/// 用量统计区间：后端 `GET usage?hours=` 支持到 1440 小时（60 天）。
enum UsageRange: Int, CaseIterable, Identifiable, Sendable {
    case days3 = 72
    case days7 = 168
    case days30 = 720
    case all = 1440

    var id: Int { rawValue }
    var hours: Int { rawValue }

    var title: String {
        switch self {
        case .days3: return "3 天"
        case .days7: return "7 天"
        case .days30: return "30 天"
        case .all: return "总计"
        }
    }

    var subtitle: String {
        switch self {
        case .days3: return "最近 72 小时"
        case .days7: return "最近 7 天"
        case .days30: return "最近 30 天"
        case .all: return "有记录以来（后端最多回看 60 天）"
        }
    }

    /// 用来算日均；总计按实际覆盖天数估，至少 1 天。
    func days(coveredHours: Double) -> Double {
        switch self {
        case .days3: return 3
        case .days7: return 7
        case .days30: return 30
        case .all: return max(coveredHours / 24, 1)
        }
    }
}

/// 区间选择器：横向胶囊 chips。
struct UsageRangePicker: View {
    @Binding var selection: UsageRange

    var body: some View {
        HStack(spacing: Metrics.s) {
            ForEach(UsageRange.allCases) { item in
                Button {
                    withAnimation(Motion.compatSnappy) { selection = item }
                } label: {
                    Text(item.title)
                        .font(.footnote.weight(selection == item ? .bold : .regular))
                        .foregroundStyle(selection == item ? Color.white : Color.primary)
                        .padding(.horizontal, Metrics.m)
                        .padding(.vertical, Metrics.s - 2)
                        .background {
                            if selection == item {
                                Capsule().fill(Accent.primary)
                            } else {
                                Capsule().fill(.quaternary.opacity(0.5))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

/// 区间消耗总览：大号 token 总量 + 请求 / 积分 / 日均。
struct UsageRangeSummaryCard: View {
    let range: UsageRange
    let totals: UsageTotals?
    var subtitleOverride: String? = nil
    var perDayOverride: String? = nil
    var missingAsDash = false

    private var tokens: Int { totals?.totalTokens ?? 0 }
    private var requests: Int { totals?.requests ?? 0 }
    private var credits: Double { totals?.credits ?? 0 }

    /// 后端窗口内的小时数：用请求桶推不出来，直接用区间定义（总计按数据起始时间估）。
    private var perDayTokens: String {
        let days = range.days(coveredHours: 24 * 30)
        return Fmt.tokens(Int(Double(tokens) / days))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            SectionHeader(title: "区间消耗", subtitle: subtitleOverride ?? range.subtitle)

            VStack(alignment: .leading, spacing: Metrics.s) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                    Text(Fmt.tokens(missingAsDash ? totals?.totalTokens : tokens))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("tokens")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: Metrics.s) {
                    stat("请求", Fmt.compact(missingAsDash ? totals?.requests : requests))
                    stat("积分", Fmt.creditsDouble(missingAsDash ? totals?.credits : credits))
                    stat("日均", perDayOverride ?? perDayTokens)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.m)
            .glassCard(padding: 0, cornerRadius: Metrics.radiusM)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.callout.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

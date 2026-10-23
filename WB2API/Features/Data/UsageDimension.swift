import Foundation

/// 用量统计的分组维度。
enum UsageDimension: String, CaseIterable, Identifiable {
    case account
    case model
    case realm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: "按账号"
        case .model: "按模型"
        case .realm: "按域"
        }
    }

    var chartTitle: String {
        switch self {
        case .account: "请求数 · 账号"
        case .model: "请求数 · 模型"
        case .realm: "请求数 · 域"
        }
    }

    var emptyDescription: String {
        switch self {
        case .account: "该区间内还没有按账号聚合的用量。"
        case .model: "该区间内还没有按模型聚合的用量。"
        case .realm: "该区间内还没有按域聚合的用量。"
        }
    }

    /// 该维度下的分组，按请求数从多到少排序。
    func groups(in snapshot: UsageSnapshot) -> [UsageGroup] {
        let raw: [UsageGroup]
        switch self {
        case .account:
            raw = snapshot.byAccount ?? []
        case .model:
            raw = snapshot.byModel ?? []
        case .realm:
            raw = snapshot.byRealm ?? []
        }
        return raw.sorted { ($0.requests ?? 0) > ($1.requests ?? 0) }
    }
}

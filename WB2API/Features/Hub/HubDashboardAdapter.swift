import Foundation

/// Rolling windows are explicit epochs, never the Hub's calendar `week`/`month` aliases.
struct HubUsageWindow: Equatable, Sendable {
    let range: UsageRange
    let end: Date
    var since: Double? {
        if range == .all || range == .today { return nil }
        return end.timeIntervalSince1970 - Double(range.hours) * 3600
    }
    var until: Double? {
        if range == .all || range == .today { return nil }
        return end.timeIntervalSince1970
    }
    var query: [URLQueryItem] {
        var items = [URLQueryItem(name: "realm", value: "all")]
        switch range {
        case .today:
            items.append(URLQueryItem(name: "range", value: "today"))
        case .all:
            items.append(URLQueryItem(name: "range", value: "all"))
        default:
            items.append(URLQueryItem(name: "range", value: "custom"))
            if let since, let until {
                items += [
                    URLQueryItem(name: "since", value: String(format: "%.3f", since)),
                    URLQueryItem(name: "until", value: String(format: "%.3f", until))
                ]
            }
        }
        return items
    }
    var subtitle: String {
        switch range {
        case .all: return "有记录以来（Hub 可用全量记录）"
        case .today: return "今天（服务器当地时间）"
        default: return range.subtitle
        }
    }
    var days: Double? {
        switch range {
        case .all: return nil
        case .today: return 1
        default: return Double(range.hours) / 24
        }
    }

    func validate(_ analytics: JSONValue) throws {
        let reported = analytics.field("window")
        guard reported.objectValue != nil else { throw HubError.rejected("Hub 未确认统计窗口，暂不展示区间数据。") }
        switch range {
        case .today:
            // 后端 range=today：window.since 为今天午夜（非空），until 为 null。
            guard reported.field("since").finiteNumber != nil,
                  reported.field("until") == .null else {
                throw HubError.rejected("Hub 返回的今日窗口与所选区间不一致，请检查后端版本。")
            }
        case .all:
            guard reported.field("since") == .null, reported.field("until") == .null else {
                throw HubError.rejected("Hub 未返回全量窗口，不能标记为总计。")
            }
        default:
            if let since, let until {
                guard let lo = reported.field("since").finiteNumber,
                      let hi = reported.field("until").finiteNumber,
                      abs(lo - since) < 0.01, abs(hi - until) < 0.01 else {
                    throw HubError.rejected("Hub 返回的统计窗口与所选区间不一致，请检查后端版本。")
                }
            }
        }
    }
}

extension JSONValue {
    var finiteNumber: Double? {
        guard let number = doubleValue, number.isFinite else { return nil }
        return number
    }
    var countNumber: Int? {
        if let n = intValue { return n >= 0 ? n : nil }
        guard let number = finiteNumber, number >= 0 else { return nil }
        return Int(exactly: number)
    }
}

/// Hub analytics `requests` counts successes; errors are a separate counter.
/// Ratios use successes/(successes+errors), excluding client_aborted as the server does.
struct HubUsageStats: Sendable {
    let raw: JSONValue
    var successes: Int? { raw.field("requests").countNumber }
    var errors: Int? { raw.field("errors").countNumber }
    var requests: Int? {
        guard let successes, let errors else { return nil }
        let sum = successes.addingReportingOverflow(errors)
        return sum.overflow ? nil : sum.partialValue
    }
    var successRate: Double? {
        guard let successes, let requests, requests > 0 else { return nil }
        return Double(successes) / Double(requests)
    }
    var cacheRate: Double? {
        guard let prompt = raw.field("prompt_tokens").finiteNumber, prompt > 0,
              let cached = raw.field("cached_tokens").finiteNumber, cached >= 0, cached <= prompt else { return nil }
        return cached / prompt * 100
    }
    var averageLatency: Double? {
        guard let count = raw.field("elapsed_n").finiteNumber, count > 0,
              let sum = raw.field("elapsed_sum").finiteNumber, sum >= 0 else { return nil }
        return sum / count
    }
    var totals: UsageTotals {
        UsageTotals(requests: requests, errors: errors,
            promptTokens: raw.field("prompt_tokens").countNumber,
            completionTokens: raw.field("completion_tokens").countNumber,
            totalTokens: raw.field("total_tokens").countNumber,
            cacheHitTokens: raw.field("cached_tokens").countNumber,
            avgLatencyMs: averageLatency, avgTokensPerSecond: raw.field("speed_n").finiteNumber.flatMap { $0 > 0 ? raw.field("speed_avg").finiteNumber : nil },
            credits: raw.field("credit").finiteNumber, creditsPer1mTokens: nil, cacheHitRate: cacheRate)
    }
}

struct HubUsagePresentation: Sendable {
    let snapshot: UsageSnapshot
    let stats: HubUsageStats
    let costCNY: Double?
    let window: HubUsageWindow
    var perDay: String {
        guard let days = window.days, days > 0, let tokens = snapshot.totals?.totalTokens,
              let value = Int(exactly: (Double(tokens) / days).rounded(.towardZero)) else { return "—" }
        return Fmt.tokens(value)
    }
}

enum HubDashboardAdapter {
    static func usage(_ document: JSONValue, window: HubUsageWindow) throws -> HubUsagePresentation {
        try window.validate(document)
        let summary = document.field("summary").field("window")
        guard summary.objectValue != nil else { throw HubError.rejected("Hub 未返回区间汇总，不能用零值代替。") }
        let stats = HubUsageStats(raw: summary)
        let accounts = document.field("accounts").arrayValue?.compactMap { row -> UsageGroup? in
            guard let uid = row.field("uid").stringValue else { return nil }
            return group(key: uid, name: row.field("nickname").stringValue, realm: row.field("realm").stringValue, raw: row.field("window"))
        }
        let models = document.field("models").arrayValue?.compactMap { row -> UsageGroup? in
            guard let model = row.field("model").stringValue else { return nil }
            return group(key: model, name: nil, realm: nil, raw: row.field("window"))
        }
        let realms = realmGroups(document.field("accounts").arrayValue)
        return HubUsagePresentation(snapshot: UsageSnapshot(totals: stats.totals, byRealm: realms, byAccount: accounts, byModel: models, series: nil, creditByAccount: nil, creditByModel: nil), stats: stats, costCNY: summary.field("cost_cny").finiteNumber, window: window)
    }

    private static func group(key: String, name: String?, realm: String?, raw: JSONValue) -> UsageGroup {
        let stats = HubUsageStats(raw: raw)
        return UsageGroup(key: key, extra: name, nickname: name, realm: realm, requests: stats.requests, errors: stats.errors, totalTokens: raw.field("total_tokens").countNumber, credits: raw.field("credit").finiteNumber, avgLatencyMs: stats.averageLatency)
    }

    private static func realmGroups(_ rows: [JSONValue]?) -> [UsageGroup]? {
        guard let rows else { return nil }
        let groups = Dictionary(grouping: rows) { $0.field("realm").stringValue ?? "unknown" }
        return groups.keys.sorted().map { realm in
            let rows = groups[realm]!
            let metrics = rows.map { HubUsageStats(raw: $0.field("window")) }
            func total(_ values: [Int?]) -> Int? {
                guard values.allSatisfy({ $0 != nil }) else { return nil }
                var result = 0
                for value in values {
                    let sum = result.addingReportingOverflow(value!)
                    guard !sum.overflow else { return nil }
                    result = sum.partialValue
                }
                return result
            }
            let credits = metrics.map { $0.totals.credits }
            return UsageGroup(key: realm, extra: realm == "cn" ? "国内版" : (realm == "intl" ? "国际版" : "未知域"), nickname: nil, realm: realm,
                requests: total(metrics.map(\.requests)), errors: total(metrics.map(\.errors)), totalTokens: total(metrics.map { $0.totals.totalTokens }),
                credits: credits.allSatisfy({ $0 != nil }) ? credits.compactMap { $0 }.reduce(0, +) : nil, avgLatencyMs: nil)
        }
    }
}

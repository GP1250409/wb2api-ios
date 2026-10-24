import Foundation

struct HubModelCooldown: Identifiable, Sendable {
    var id: String { realm + "|" + model }
    let model: String
    let realm: String
    let affected: Int
    let earliest: Date
    var realmLabel: String { realm == "cn" ? "国内版" : (realm == "intl" ? "国际版" : "未知域") }
}

struct HubOverviewPresentation: Sendable {
    let health: JSONValue
    let accountsDocument: JSONValue
    let todayDocument: JSONValue
    let trend: UsageSnapshot?
    var accounts: [JSONValue]? { accountsDocument.field("accounts").arrayValue }
    var total: Int? { health.field("accounts").countNumber ?? accounts.map(\.count) }
    var ready: Int? {
        guard let value = health.field("accounts_ready").countNumber,
              total.map({ value <= $0 }) ?? true else { return nil }
        return value
    }
    var ratio: Double? {
        guard let total, total > 0, let ready, ready <= total else { return nil }
        return Double(ready) / Double(total)
    }
    var headline: String {
        guard let total else { return "等待账号池数据" }
        if total == 0 { return "等待账号接入" }
        guard let ready, let ratio else { return "账号状态未完整提供" }
        if ready == total { return "池子状态良好" }
        return ratio >= 0.6 ? "部分账号需要关注" : "池子压力较大"
    }
    var creditValues: [Double]? {
        accounts.map { $0.compactMap { $0.field("credits").field("remain").finiteNumber } }
    }
    var credits: Double? {
        guard let values = creditValues, let accounts,
              !values.isEmpty || accounts.isEmpty else { return nil }
        let total = values.reduce(0, +)
        return total.isFinite ? total : nil
    }
    var creditCaption: String {
        guard let accounts, let creditValues else { return "积分缓存未提供" }
        return accounts.count == creditValues.count ? "全部账号缓存合计" : "已知 \(creditValues.count)/\(accounts.count) 个账号合计"
    }
    var today: HubUsageStats? {
        let raw = todayDocument.field("summary").field("window")
        return raw.objectValue == nil ? nil : HubUsageStats(raw: raw)
    }
    private func flagCount(_ key: String, value: Bool = true) -> Int? {
        guard let accounts, accounts.allSatisfy({ $0.field(key).boolValue != nil }) else { return nil }
        return accounts.filter { $0.field(key).boolValue == value }.count
    }
    var paused: Int? { flagCount("enabled", value: false) }
    var cooling: Int? { flagCount("inCooldown") }
    var expired: Int? { flagCount("tokenExpired") }
    var expiryText: String? {
        guard let accounts else { return nil }
        let values = accounts.compactMap { row -> (String, Double)? in
            let expiry = row.field("credits").field("earliest_expiring")
            guard let date = expiry.field("cycle_end_time").stringValue,
                  date.range(of: "^\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) != nil,
                  let remain = expiry.field("remain").finiteNumber else { return nil }
            return (String(date.prefix(10)), remain)
        }
        guard let first = values.min(by: { $0.0 < $1.0 }) else { return nil }
        // Show the server's date, do not guess a timezone for a timezone-less upstream timestamp.
        return "已知积分到期 \(first.0.suffix(5)) · 剩 \(HubDashboardFormat.credits(first.1)) 分"
    }
    func cooldowns(now: Date = Date()) -> [HubModelCooldown]? {
        guard let accounts, accounts.allSatisfy({ $0.field("modelCooldowns").arrayValue != nil }) else { return nil }
        var items: [String: (String, String, Set<String>, Date)] = [:]
        for (index, account) in accounts.enumerated() {
            for row in account.field("modelCooldowns").arrayValue ?? [] {
                guard let model = row.field("model").stringValue,
                      let epoch = row.field("expiresAt").finiteNumber, epoch > now.timeIntervalSince1970 else { continue }
                let realm = account.field("realm").stringValue ?? "unknown"
                let key = realm + "|" + model
                let date = Date(timeIntervalSince1970: epoch)
                var value = items[key] ?? (model, realm, Set<String>(), date)
                value.2.insert(account.field("uid").stringValue ?? "row-\(index)")
                value.3 = min(value.3, date)
                items[key] = value
            }
        }
        return items.keys.sorted().map {
            let v = items[$0]!
            return HubModelCooldown(model: v.0, realm: v.1, affected: v.2.count, earliest: v.3)
        }
    }
}

enum HubDashboardFormat {
    static func credits(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if abs(value) >= 10_000 { return String(format: "%.1fk", value / 1000) }
        return Fmt.creditsDouble(value)
    }
    static func money(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "¥%.2f", value)
    }
}

extension HubDashboardAdapter {
    static func trend(_ document: JSONValue, since: Double, until: Double, timeZone: TimeZone = .current) throws -> UsageSnapshot {
        guard until > since, until - since <= 86400.01,
              document.field("ok").boolValue == true,
              document.field("bucket_seconds").countNumber == 3600,
              let lo = document.field("since").finiteNumber, abs(lo - since) < 0.01,
              let hi = document.field("until").finiteNumber, abs(hi - until) < 0.01,
              let rows = document.field("series").arrayValue else {
            throw HubError.rejected("Hub 未返回所请求的小时趋势窗口")
        }
        var points: [Double: UsagePoint] = [:]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH"
        for row in rows {
            guard let at = row.field("at").finiteNumber, at >= lo - 3600, at <= hi,
                  let tokens = row.field("total_tokens").countNumber,
                  let requests = row.field("requests").countNumber, points[at] == nil else {
                throw HubError.rejected("小时趋势桶缺少数据或时间重复，不能补造数值")
            }
            points[at] = UsagePoint(t: formatter.string(from: Date(timeIntervalSince1970: at)), key: nil, requests: requests, tokens: nil, totalTokens: tokens, credits: row.field("credit").finiteNumber)
        }
        var series: [UsagePoint] = []
        if let first = points.keys.min() {
            guard points.keys.allSatisfy({ abs(($0 - first) / 3600 - (($0 - first) / 3600).rounded()) < 0.00001 }) else {
                throw HubError.rejected("小时趋势桶没有对齐，不能将错位数据补成零")
            }
            // Server returns only nonempty buckets; absent buckets are zero only after validating the complete response window.
            var cursor = first - ceil((first - lo) / 3600) * 3600
            while cursor <= hi && series.count < 26 {
                series.append(points[cursor] ?? UsagePoint(t: formatter.string(from: Date(timeIntervalSince1970: cursor)), key: nil, requests: 0, tokens: nil, totalTokens: 0, credits: 0))
                cursor += 3600
            }
        }
        return UsageSnapshot(totals: nil, byRealm: nil, byAccount: nil, byModel: nil, series: series, creditByAccount: nil, creditByModel: nil)
    }
}

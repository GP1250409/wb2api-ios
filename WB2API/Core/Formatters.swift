import Foundation

/// 展示层格式化：所有"给人看的字符串"都从这里出，便于单测。
enum Fmt {
    // MARK: 数字

    static func credits(_ value: Int?) -> String {
        guard let value else { return "—" }
        if value >= 10_000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func compact(_ value: Int?) -> String {
        guard let value else { return "—" }
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...: return String(format: "%.1fk", Double(value) / 1000)
        default: return "\(value)"
        }
    }

    static func percent(_ value: Double?, digits: Int = 1) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f%%", value * 100)
    }

    static func latency(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        return ms >= 1000 ? String(format: "%.1fs", ms / 1000) : String(format: "%.0fms", ms)
    }

    static func creditsDouble(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }

    // MARK: 时间

    /// 后端时间可能是 RFC3339（带时区/毫秒）或 "2006-01-02 15:04:05"。
    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            df.dateFormat = pattern
            if let d = df.date(from: raw) { return d }
        }
        return nil
    }

    /// 相对时间：刚刚 / 3 分钟前 / 2 小时前 / 昨天 / 10-21
    static func ago(_ raw: String?, now: Date = Date()) -> String {
        guard let date = parse(raw) else { return "—" }
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "刚刚" }
        if delta < 3600 { return "\(Int(delta / 60)) 分钟前" }
        if delta < 86_400 { return "\(Int(delta / 3600)) 小时前" }
        if delta < 172_800 { return "昨天" }
        let df = DateFormatter()
        df.dateFormat = "MM-dd"
        return df.string(from: date)
    }

    /// 倒计时：4 分 32 秒 / 2 小时 5 分
    static func countdown(until raw: String?, now: Date = Date()) -> String? {
        guard let date = parse(raw) else { return nil }
        let delta = date.timeIntervalSince(now)
        guard delta > 0 else { return nil }
        if delta < 60 { return "\(Int(delta)) 秒" }
        if delta < 3600 { return "\(Int(delta / 60)) 分 \(Int(delta.truncatingRemainder(dividingBy: 60))) 秒" }
        return "\(Int(delta / 3600)) 小时 \(Int((delta.truncatingRemainder(dividingBy: 3600)) / 60)) 分"
    }

    static func clock(_ raw: String?) -> String {
        guard let date = parse(raw) else { return "—" }
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df.string(from: date)
    }

    static func day(_ raw: String?) -> String {
        guard let date = parse(raw) else { return raw ?? "—" }
        let df = DateFormatter()
        df.dateFormat = "MM-dd"
        return df.string(from: date)
    }

    // MARK: 状态

    static func accountState(_ account: Account) -> String {
        if account.isDisabled { return "已禁用" }
        if account.isCooling {
            if let left = countdown(until: account.until) { return "冷却中 · \(left)后恢复" }
            return "冷却中"
        }
        return "可用"
    }
}

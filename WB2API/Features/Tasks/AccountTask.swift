import SwiftUI

/// 扫描结果里单个任务的展示模型（从 `growth` 数组拍平）。
struct AccountTask: Identifiable, Sendable, Equatable {
    let uid: String
    let nickname: String
    let realm: String
    let code: String
    let title: String
    let description: String?
    let acceptStatus: String?
    let current: Int?
    let target: Int?
    let hasReward: Bool
    let credit: Int?

    var id: String { "\(uid)-\(code)" }

    /// 可接受：未 accepted / completed
    var canAccept: Bool {
        acceptStatus != "accepted" && acceptStatus != "completed"
    }

    /// 可领取：已完成且未领（有 reward 且进度已满）
    var canClaim: Bool {
        guard hasReward else { return false }
        if let c = current, let t = target, t > 0 {
            return c >= t
        }
        return acceptStatus == "completed"
    }

    var progressText: String? {
        guard let c = current, let t = target, t > 0 else { return nil }
        return "\(c)/\(t)"
    }

    var statusText: String {
        switch acceptStatus {
        case "completed": return "已完成"
        case "accepted": return "进行中"
        case "claimed": return "已领取"
        default: return "未接受"
        }
    }

    var statusTint: Color {
        switch acceptStatus {
        case "completed", "claimed": return .green
        case "accepted": return Accent.primary
        default: return .orange
        }
    }
}

/// scan_all / 单号 tasks 响应 → [AccountTask]
enum AccountTaskParser {
    /// `POST tasks/scan_all`：`{ok, accounts:[{uid,nickname,realm,skipped,growth:[…]}], pending_count}`
    static func fromScan(_ value: JSONValue) -> [AccountTask] {
        guard let accounts = value.objectValue?["accounts"]?.arrayValue else { return [] }
        return accounts.flatMap { entry(from: $0) }
    }

    /// `GET accounts/{uid}/tasks`：`{ok, tasks:[…]}`（无昵称，传空由上层补）
    static func fromSingle(_ value: JSONValue, uid: String, nickname: String?, realm: String?) -> [AccountTask] {
        let tasks = value.objectValue?["tasks"]?.arrayValue ?? []
        return tasks.compactMap { task(from: $0, uid: uid, nickname: nickname, realm: realm) }
    }

    private static func entry(from account: JSONValue) -> [AccountTask] {
        let uid = account.objectValue?["uid"]?.stringValue ?? ""
        let nickname = account.objectValue?["nickname"]?.stringValue
        let realm = account.objectValue?["realm"]?.stringValue
        let growth = account.objectValue?["growth"]?.arrayValue ?? []
        return growth.compactMap { task(from: $0, uid: uid, nickname: nickname, realm: realm) }
    }

    private static func task(from raw: JSONValue, uid: String, nickname: String?, realm: String?) -> AccountTask? {
        guard let obj = raw.objectValue else { return nil }
        guard let code = obj["task_code"]?.stringValue else { return nil }
        return AccountTask(
            uid: uid,
            nickname: nickname ?? "",
            realm: realm ?? "cn",
            code: code,
            title: obj["title"]?.stringValue ?? obj["task_desc"]?.stringValue ?? code,
            description: obj["description"]?.stringValue,
            acceptStatus: obj["accept_status"]?.stringValue,
            current: obj["current"]?.intValue,
            target: obj["target"]?.intValue,
            hasReward: obj["has_reward"]?.boolValue ?? false,
            credit: obj["credit"]?.intValue
        )
    }
}

import Foundation

/// 面板操作返回值的统一解读。
///
/// 后端不同端点返回的自由 JSON 形状不一（`{"ok":true,"message":"…"}`、
/// `{"error":"…"}`、纯字符串、甚至 `null`），这里把它们收敛成 `ok` + 一句人话，
/// 避免每个调用点各写一套解包。
struct ActionOutcome: Sendable {
    let ok: Bool
    let message: String?

    init(_ value: JSONValue) {
        guard let object = value.objectValue else {
            if case .string(let text) = value, !text.isEmpty {
                ok = true
                message = text
            } else {
                ok = true
                message = nil
            }
            return
        }

        ok = object["ok"]?.boolValue ?? object["success"]?.boolValue ?? true
        message = object["message"]?.stringValue
            ?? object["error"]?.stringValue
            ?? object["msg"]?.stringValue
    }
}

extension Error {
    /// 面向用户的一句话错误描述（`APIError` 已在底层做过清洗）。
    var humanMessage: String {
        (self as? APIError)?.errorDescription ?? localizedDescription
    }
}

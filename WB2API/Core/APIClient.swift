import Foundation

// MARK: - 错误

enum APIError: LocalizedError, Equatable {
    case unauthorized
    case http(Int, String?)
    case decoding(String)
    case transport(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "密钥无效或未填写"
        case .http(let code, let msg): return msg?.isEmpty == false ? msg : "HTTP \(code)"
        case .decoding(let detail): return "数据解析失败：\(detail)"
        case .transport(let detail): return detail
        case .invalidURL: return "服务器地址无效"
        }
    }
}

// MARK: - 客户端

/// 与 WorkBuddy2API 面板通信的唯一入口。
/// 所有请求走 `Authorization: Bearer <api_key>`；401 统一映射为 `.unauthorized` 以便上层弹密钥输入。
struct APIClient: Sendable {
    var baseURL: URL
    var apiKey: String
    var session: URLSession

    init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: 基础请求

    private func request(path: String, method: String, query: [URLQueryItem], body: Data?) throws -> URLRequest {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    /// 把上游返回的 HTML 错误页压成一句人话，避免把整段 HTML 丢给用户。
    private static func humanMessage(_ raw: String, code: Int) -> String {
        let stripped = raw
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty { return "HTTP \(code)" }
        return "\(stripped.prefix(120))"
    }

    private func execute(_ req: URLRequest) async throws -> Data {        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            // 取消必须原样抛出：包成 transport 后上层就认不出来了，会误报「cancelled」
            if error.isCancellation { throw error }
            throw APIError.transport(error.humanMessage)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("无 HTTP 响应")
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let raw = String(data: data.prefix(600), encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, Self.humanMessage(raw, code: http.statusCode))
        }
        return data
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        let req = try request(path: path, method: "GET", query: query, body: nil)
        let data = try await execute(req)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func post<T: Decodable>(_ path: String, query: [URLQueryItem] = [], body: (any Encodable)? = nil, as type: T.Type = T.self) async throws -> T {
        var data: Data?
        if let body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            data = try? encoder.encode(AnyEncodable(body))
        }
        let req = try request(path: path, method: "POST", query: query, body: data)
        let raw = try await execute(req)
        do {
            return try Self.decoder.decode(T.self, from: raw)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    @discardableResult
    func postVoid(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        let req = try request(path: path, method: "POST", query: query, body: nil)
        return try await execute(req)
    }
}

/// 类型擦除，用于可选 body。
struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { encodeImpl = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeImpl(encoder) }
}

// MARK: - 端点

extension APIClient {
    static let apiPrefix = "panel/api"

    /// 账号状态。公网 nginx 只代理 `/panel/` 与 `/v1/`，根路径 `/status` 返回 404，
    /// 因此 404 时自动回退到 `/panel/api/overview`（返回同样的账号数组）。
    func status() async throws -> StatusResponse {
        do {
            return try await get("status")
        } catch APIError.http(let code, _) where code == 404 {
            let overview: OverviewResponse = try await get("\(Self.apiPrefix)/overview")
            return StatusResponse(
                accounts: overview.accounts,
                healthy: overview.healthy,
                cooling: overview.cooling,
                disabled: overview.disabled,
                inFlightFull: overview.inFlightFull
            )
        }
    }

    func overview() async throws -> OverviewResponse {
        try await get("\(Self.apiPrefix)/overview")
    }

    func models() async throws -> ModelsResponse {
        try await get("\(Self.apiPrefix)/models")
    }

    func modelProbes() async throws -> JSONValue {
        try await get("\(Self.apiPrefix)/model_probes")
    }

    func logs() async throws -> LogsResponse {
        try await get("\(Self.apiPrefix)/logs")
    }

    func requestLogs(limit: Int = 200) async throws -> JSONValue {
        try await get("\(Self.apiPrefix)/request_logs", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func requestMetrics() async throws -> RequestMetrics {
        try await get("\(Self.apiPrefix)/request_metrics")
    }

    func errorSummary() async throws -> ErrorSummary {
        try await get("\(Self.apiPrefix)/error_summary")
    }

    func taskQueue() async throws -> TaskQueue {
        try await get("\(Self.apiPrefix)/tasks/queue")
    }

    func taskJobs() async throws -> JSONValue {
        try await get("\(Self.apiPrefix)/tasks/jobs")
    }

    func usage() async throws -> UsageSnapshot {
        try await get("\(Self.apiPrefix)/usage")
    }

    func balanceHistory(days: Int = 7) async throws -> BalanceHistory {
        try await get("\(Self.apiPrefix)/balance_history", query: [URLQueryItem(name: "days", value: String(days))])
    }

    func creditHistory(limit: Int = 100) async throws -> CreditHistory {
        try await get("\(Self.apiPrefix)/credit_history", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func packages() async throws -> PackagesResponse {
        try await get("\(Self.apiPrefix)/packages")
    }

    func vouchers() async throws -> JSONValue {
        try await get("\(Self.apiPrefix)/school/vouchers")
    }

    func compensation() async throws -> JSONValue {
        try await get("\(Self.apiPrefix)/compensation")
    }

    func config() async throws -> ConfigResponse {
        try await get("\(Self.apiPrefix)/config")
    }

    func saveConfig(_ config: JSONValue) async throws -> JSONValue {
        struct Body: Encodable { let config: JSONValue }
        return try await post("\(Self.apiPrefix)/config", body: Body(config: config))
    }

    func loginRegions() async throws -> LoginRegionsResponse {
        try await get("\(Self.apiPrefix)/login/regions")
    }

    func loginStart(realm: String) async throws -> LoginStartResponse {
        struct Body: Encodable { let realm: String }
        return try await post("\(Self.apiPrefix)/login/start", body: Body(realm: realm))
    }

    func loginPoll(state: String) async throws -> LoginPollResponse {
        try await get("\(Self.apiPrefix)/login/poll", query: [URLQueryItem(name: "state", value: state)])
    }

    // 单号操作
    func accountAction(_ uid: String, action: String) async throws -> JSONValue {
        try await post("\(Self.apiPrefix)/accounts/\(uid)/\(action)")
    }

    func modelToggle(uid: String, model: String, enabled: Bool) async throws -> JSONValue {
        struct Body: Encodable { let model: String; let enabled: Bool }
        return try await post("\(Self.apiPrefix)/accounts/\(uid)/model_toggle", body: Body(model: model, enabled: enabled))
    }

    func accountTasks(uid: String) async throws -> JSONValue {
        try await get("\(Self.apiPrefix)/accounts/\(uid)/tasks")
    }

    /// 接受任务（可多个 task_codes，幂等）
    func acceptTasks(uid: String, codes: [String]) async throws -> JSONValue {
        struct Body: Encodable { let taskCodes: [String] }
        return try await post("\(Self.apiPrefix)/accounts/\(uid)/tasks/accept", body: Body(taskCodes: codes))
    }

    /// 领取单个任务奖励（未达标时上游报业务错误）
    func claimTask(uid: String, code: String) async throws -> JSONValue {
        struct Body: Encodable { let taskCode: String }
        return try await post("\(Self.apiPrefix)/accounts/\(uid)/tasks/claim", body: Body(taskCode: code))
    }

    /// 扫描全部账号任务（返回每账号任务明细，用于逐项操作）
    func scanAllTasks() async throws -> JSONValue {
        try await post("\(Self.apiPrefix)/tasks/scan_all")
    }

    /// 暂停执行队列：当前任务跑完后，剩余任务不再执行
    func pauseTaskQueue() async throws -> JSONValue {
        try await post("\(Self.apiPrefix)/tasks/pause")
    }

    // 批量操作
    func batch(_ action: String) async throws -> JSONValue {
        try await post("\(Self.apiPrefix)/\(action)")
    }

    func importCockpit(_ payload: Data) async throws -> JSONValue {
        let req = try request(path: "\(Self.apiPrefix)/import/cockpit", method: "POST", query: [], body: payload)
        let raw = try await execute(req)
        return (try? Self.decoder.decode(JSONValue.self, from: raw)) ?? .null
    }
}

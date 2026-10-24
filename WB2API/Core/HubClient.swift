import Foundation

enum HubError: LocalizedError, Equatable {
    case invalidPassword, sessionExpired, invalidLoginResponse
    case rejected(String)
    var errorDescription: String? {
        switch self {
        case .invalidPassword: return "DM/Hub 面板密码不正确。这里需要面板登录密码，不是 API Key。"
        case .sessionExpired: return "此 Hub 面板登录已过期，请在「更多」中重新登录；其他服务器不受影响。"
        case .invalidLoginResponse: return "Hub 登录响应不符合预期，请检查服务器类型和地址。"
        case .rejected(let message): return message
        }
    }
}

/// Hub has a separate API contract. Never put its panel session into a Bearer header.
struct HubClient: Sendable {
    let baseURL: URL
    let token: String
    var session: URLSession = .panel

    func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: JSONValue? = nil, timeout: TimeInterval = 60) async throws -> JSONValue {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if path != "panel/login", !token.isEmpty { request.setValue(token, forHTTPHeaderField: "X-Panel-Token") }
        if let cookie = await AccessCookieBridge.header(for: url) { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("没有 HTTP 响应") }
        do { try APIClient.validateResponse(http, data: data) }
        catch APIError.unauthorized { throw path == "panel/login" ? HubError.invalidPassword : HubError.sessionExpired }
        do { return try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw APIError.decoding("Hub 接口未返回有效 JSON") }
    }

    func login(password: String) async throws -> String {
        let response = try await request("panel/login", method: "POST", body: .object(["password": .string(password)]))
        guard response.field("ok").boolValue == true,
              let token = response.field("token").stringValue, !token.isEmpty else { throw HubError.invalidLoginResponse }
        return token
    }

    func verifySession() async throws {
        let response = try await request("panel/status")
        guard response.field("authenticated").boolValue == true else { throw HubError.sessionExpired }
    }

    func accounts() async throws -> JSONValue {
        let response = try await request("accounts", query: [URLQueryItem(name: "realm", value: "all")])
        guard response.field("accounts").arrayValue != nil else { throw HubError.rejected("Hub 账号响应结构不符合预期") }
        return response
    }

    func perform(_ path: String, body: JSONValue) async throws -> JSONValue {
        let response = try await request(path, method: "POST", body: body, timeout: 300)
        if response.field("ok").boolValue == false {
            throw HubError.rejected(response.field("msg").stringValue ?? "Hub 拒绝了操作")
        }
        return response
    }
}

extension JSONValue {
    /// Case-preserving field access: Hub uses both camelCase and snake_case keys.
    func field(_ key: String) -> JSONValue { objectValue?[key] ?? .null }
}

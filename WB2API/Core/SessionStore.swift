import Foundation
import Observation

/// 全局会话：服务器地址 + api_key + 客户端工厂。
/// 地址存 UserDefaults，密钥存 Keychain。
@MainActor
@Observable
final class SessionStore {
    static let defaultBaseURL = "https://panel.example.com"

    private static let baseURLKey = "wb2api.baseURL"

    var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Self.baseURLKey) }
    }

    private(set) var apiKey: String
    var isConfigured: Bool { !apiKey.isEmpty && URL(string: baseURLString) != nil }

    init() {
        baseURLString = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURL
        apiKey = Keychain.read() ?? ""
    }

    var baseURL: URL? {
        var s = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    func client(session: URLSession = .shared) -> APIClient? {
        guard let baseURL else { return nil }
        return APIClient(baseURL: baseURL, apiKey: apiKey, session: session)
    }

    func update(apiKey newValue: String) {
        apiKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey.isEmpty {
            Keychain.delete()
        } else {
            Keychain.save(apiKey)
        }
    }

    func signOut() {
        update(apiKey: "")
    }
}

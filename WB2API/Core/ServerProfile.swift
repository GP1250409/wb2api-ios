import Foundation
import CryptoKit

enum BackendKind: String, Codable, CaseIterable, Identifiable {
    case panel, hub
    var id: String { rawValue }
    var title: String { self == .panel ? "Panel（RN）" : "Hub（DM）" }
    var accessProbe: String { self == .panel ? "panel/api/overview" : "panel/status" }
}

/// Only non-secret connection metadata is encoded to UserDefaults.
struct ServerProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var address: String
    var backend: BackendKind

    static let defaults = [
        ServerProfile(id: "rn", name: "RN", address: "https://rnwb.gpcpa.cc.cd", backend: .panel),
        ServerProfile(id: "dm", name: "DM", address: "https://dmwb.gpcpa.cc.cd", backend: .hub)
    ]

    static func normalizedURL(_ text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard var c = URLComponents(string: text),
              let scheme = c.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = c.host?.lowercased(), !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil else { return nil }
        c.scheme = scheme
        c.host = host
        if (scheme == "https" && c.port == 443) || (scheme == "http" && c.port == 80) { c.port = nil }
        while c.path.hasSuffix("/") { c.path.removeLast() }
        return c.url
    }

    var url: URL? { Self.normalizedURL(address) }
    var credentialAccount: String? {
        guard let url else { return nil }
        let scope = backend.rawValue + "|" + url.absoluteString
        let digest = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return "profile." + id + "." + digest
    }
}

protocol ProfileCredentialStorage {
    func read(_ account: String) -> String?
    func save(_ value: String, account: String) -> Bool
    func delete(_ account: String)
}

struct SystemProfileCredentialStorage: ProfileCredentialStorage {
    func read(_ account: String) -> String? { Keychain.read(account: account) }
    func save(_ value: String, account: String) -> Bool { Keychain.save(value, account: account) }
    func delete(_ account: String) { Keychain.delete(account: account) }
}

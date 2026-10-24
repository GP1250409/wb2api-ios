import Foundation
import Combine

/// Each profile has an origin/backend-scoped Keychain credential; no password is persisted.
@MainActor
final class SessionStore: ObservableObject {
    static let defaultBaseURL = ""
    private let defaults: UserDefaults
    private let vault: any ProfileCredentialStorage
    private var restoring = false
    private var credentialRefs: [String: [String]]

    @Published private(set) var profiles: [ServerProfile]
    @Published private(set) var activeProfileID: String
    @Published private(set) var revision = UUID()
    @Published private(set) var apiKey = ""
    @Published private(set) var hubToken = ""
    @Published private(set) var credentialError: String?
    @Published var baseURLString: String {
        didSet {
            guard !restoring, let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
            profiles[index].address = baseURLString
            loadCredential()
            persist()
        }
    }

    var activeProfile: ServerProfile { profiles.first { $0.id == activeProfileID } ?? profiles[0] }
    var backend: BackendKind { activeProfile.backend }
    var baseURL: URL? { ServerProfile.normalizedURL(baseURLString) }
    var isConfigured: Bool { baseURL != nil && !(backend == .panel ? apiKey : hubToken).isEmpty }

    init(defaults: UserDefaults = .standard, vault: any ProfileCredentialStorage = SystemProfileCredentialStorage()) {
        self.defaults = defaults
        self.vault = vault
        credentialRefs = defaults.dictionary(forKey: "wb2api.credentialRefs") as? [String: [String]] ?? [:]
        let saved = defaults.data(forKey: "wb2api.profiles").flatMap { try? JSONDecoder().decode([ServerProfile].self, from: $0) }
        var list = saved?.isEmpty == false ? saved! : ServerProfile.defaults
        if saved == nil, let legacy = defaults.string(forKey: "wb2api.baseURL"), !legacy.isEmpty,
           ServerProfile.normalizedURL(legacy)?.host != "dmwb.gpcpa.cc.cd" {
            list[0].address = legacy
        }
        profiles = list
        let requested = defaults.string(forKey: "wb2api.activeProfile") ?? list[0].id
        let selected = list.contains { $0.id == requested } ? requested : list[0].id
        activeProfileID = selected
        baseURLString = list.first { $0.id == selected }!.address
        // Migrate the old single RN key once. Never reinterpret an API key as a Hub session token.
        if saved == nil, let rn = list.first(where: { $0.backend == .panel }),
           let account = rn.credentialAccount, let old = vault.read("api_key"), !old.isEmpty,
           vault.save(old, account: account) {
            credentialRefs[rn.id, default: []].append(account)
            vault.delete("api_key")
        }
        loadCredential()
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(profiles), forKey: "wb2api.profiles")
        defaults.set(activeProfileID, forKey: "wb2api.activeProfile")
        defaults.set(credentialRefs, forKey: "wb2api.credentialRefs")
    }

    private func loadCredential() {
        let value = activeProfile.credentialAccount.flatMap { vault.read($0) } ?? ""
        apiKey = backend == .panel ? value : ""
        hubToken = backend == .hub ? value : ""
        credentialError = nil
    }

    func selectProfile(_ id: String) {
        guard let profile = profiles.first(where: { $0.id == id }), id != activeProfileID else { return }
        restoring = true
        activeProfileID = id
        baseURLString = profile.address
        restoring = false
        loadCredential()
        revision = UUID() // Destroys old view/loaders so data cannot bleed into the new server.
        persist()
    }

    func saveProfile(_ profile: ServerProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        if activeProfileID == profile.id {
            restoring = true
            baseURLString = profile.address
            restoring = false
            loadCredential()
            revision = UUID()
        }
        persist()
    }

    func removeProfile(_ id: String) {
        guard profiles.count > 1 else { return }
        for account in credentialRefs[id] ?? [] { vault.delete(account) }
        credentialRefs[id] = nil
        if activeProfileID == id, let next = profiles.first(where: { $0.id != id }) { selectProfile(next.id) }
        profiles.removeAll { $0.id == id }
        persist()
    }

    func client(session: URLSession = .panel, for scope: UUID? = nil) -> APIClient? {
        guard scope == nil || scope == revision else { return nil }
        guard backend == .panel, let baseURL else { return nil }
        return APIClient(baseURL: baseURL, apiKey: apiKey, session: session)
    }

    func hubClient(session: URLSession = .panel) -> HubClient? {
        guard backend == .hub, let baseURL else { return nil }
        return HubClient(baseURL: baseURL, token: hubToken, session: session)
    }

    @discardableResult
    func update(apiKey newValue: String) -> Bool {
        guard backend == .panel else { return false }
        return storeCredential(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @discardableResult
    func updateHubToken(_ token: String) -> Bool {
        guard backend == .hub else { return false }
        return storeCredential(token)
    }

    private func storeCredential(_ value: String) -> Bool {
        guard let account = activeProfile.credentialAccount else { return false }
        if value.isEmpty { vault.delete(account) }
        else {
            guard vault.save(value, account: account) else {
                credentialError = "无法将凭据保存到本机钥匙串，请检查安装签名权限。"
                return false
            }
            if !credentialRefs[activeProfileID, default: []].contains(account) {
                credentialRefs[activeProfileID, default: []].append(account)
            }
        }
        loadCredential()
        persist()
        return true
    }

    func signOut() {
        _ = storeCredential("")
        revision = UUID()
    }
}

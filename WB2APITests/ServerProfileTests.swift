import XCTest
@testable import WB2API

final class MemoryProfileVault: ProfileCredentialStorage {
    var values: [String: String] = [:]
    var failWrites = false
    func read(_ account: String) -> String? { values[account] }
    func save(_ value: String, account: String) -> Bool {
        guard !failWrites else { return false }
        values[account] = value
        return true
    }
    func delete(_ account: String) { values[account] = nil }
}

final class ServerProfileTests: XCTestCase {
    @MainActor private func fixture() -> (SessionStore, MemoryProfileVault, UserDefaults, String) {
        let name = "WB2API.ProfileTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let vault = MemoryProfileVault()
        return (SessionStore(defaults: defaults, vault: vault), vault, defaults, name)
    }

    @MainActor func testRNAndDMKeepSeparateCredentialsWhenSwitching() {
        let (store, _, defaults, name) = fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(store.update(apiKey: "rn-unit-test-key"))
        let revision = store.revision
        store.selectProfile("dm")
        XCTAssertNotEqual(store.revision, revision)
        XCTAssertEqual(store.apiKey, "")
        XCTAssertNil(store.client())
        XCTAssertFalse(store.isConfigured)
        XCTAssertTrue(store.updateHubToken("dm-unit-test-session"))
        store.selectProfile("rn")
        XCTAssertEqual(store.apiKey, "rn-unit-test-key")
        XCTAssertEqual(store.hubToken, "")
        XCTAssertNil(store.hubClient())
        store.selectProfile("dm")
        XCTAssertEqual(store.hubToken, "dm-unit-test-session")
    }

    @MainActor func testSignOutOfDMDoesNotClearRN() {
        let (store, _, defaults, name) = fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        store.update(apiKey: "rn-unit-test-key")
        store.selectProfile("dm")
        store.updateHubToken("dm-unit-test-session")
        store.signOut()
        XCTAssertFalse(store.isConfigured)
        store.selectProfile("rn")
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(store.apiKey, "rn-unit-test-key")
    }

    @MainActor func testChangingOriginNeverReusesOldCredential() {
        let (store, _, defaults, name) = fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        store.update(apiKey: "rn-unit-test-key")
        store.baseURLString = "https://other.example.com"
        XCTAssertFalse(store.isConfigured)
        XCTAssertEqual(store.apiKey, "")
        store.baseURLString = "https://rnwb.gpcpa.cc.cd/"
        XCTAssertEqual(store.apiKey, "rn-unit-test-key")
    }

    @MainActor func testBackendChangeDoesNotReinterpretAPIKeyAsPanelToken() {
        let (store, _, defaults, name) = fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        store.update(apiKey: "rn-unit-test-key")
        var profile = store.activeProfile
        profile.backend = .hub
        store.saveProfile(profile)
        XCTAssertEqual(store.hubToken, "")
        XCTAssertFalse(store.isConfigured)
    }

    @MainActor func testPersistedProfilesContainNoSecretsAndRestartRestoresDM() {
        let (store, vault, defaults, name) = fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        store.update(apiKey: "rn-unit-test-secret")
        store.selectProfile("dm")
        store.updateHubToken("dm-unit-test-secret")
        let encoded = String(data: defaults.data(forKey: "wb2api.profiles")!, encoding: .utf8)!
        XCTAssertFalse(encoded.contains("rn-unit-test-secret"))
        XCTAssertFalse(encoded.contains("dm-unit-test-secret"))
        let restored = SessionStore(defaults: defaults, vault: vault)
        XCTAssertEqual(restored.activeProfileID, "dm")
        XCTAssertEqual(restored.hubToken, "dm-unit-test-secret")
        XCTAssertEqual(restored.apiKey, "")
    }

    @MainActor func testLegacyRNKeyMigratesWithoutBecomingDMToken() {
        let name = "WB2API.ProfileTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("https://rnwb.gpcpa.cc.cd", forKey: "wb2api.baseURL")
        let vault = MemoryProfileVault()
        vault.values["api_key"] = "legacy-unit-test-key"
        let store = SessionStore(defaults: defaults, vault: vault)
        XCTAssertEqual(store.apiKey, "legacy-unit-test-key")
        XCTAssertNil(vault.values["api_key"])
        store.selectProfile("dm")
        XCTAssertEqual(store.hubToken, "")
    }

    @MainActor func testDeletingOneProfileDoesNotRemoveOtherProfileLogin() {
        let (store, _, defaults, name) = fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        store.update(apiKey: "rn-unit-test-key")
        store.selectProfile("dm")
        store.updateHubToken("dm-unit-test-session")
        store.removeProfile("dm")
        XCTAssertEqual(store.activeProfileID, "rn")
        XCTAssertEqual(store.apiKey, "rn-unit-test-key")
        XCTAssertEqual(store.profiles.count, 1)
    }

    @MainActor func testFailedKeychainWriteDoesNotClaimSuccessfulLogin() {
        let (store, vault, defaults, name) = fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        vault.failWrites = true
        XCTAssertFalse(store.update(apiKey: "unit-test-secret"))
        XCTAssertFalse(store.isConfigured)
        XCTAssertNotNil(store.credentialError)
    }

    func testCredentialScopeNormalizesURLButDistinguishesPortPathAndBackend() {
        let p = ServerProfile.defaults[0]
        var equivalent = p
        equivalent.address = "https://RNWB.GPCPA.CC.CD:443/"
        XCTAssertEqual(p.credentialAccount, equivalent.credentialAccount)
        equivalent.address = "https://rnwb.gpcpa.cc.cd:8443"
        XCTAssertNotEqual(p.credentialAccount, equivalent.credentialAccount)
        XCTAssertNil(ServerProfile.normalizedURL("https://user:secret@example.com"))
        XCTAssertEqual(BackendKind.hub.accessProbe, "panel/status")
        XCTAssertEqual(BackendKind.panel.accessProbe, "panel/api/overview")
    }
}

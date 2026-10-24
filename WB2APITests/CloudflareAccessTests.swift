import XCTest
import WebKit
@testable import WB2API

final class CloudflareAccessTests: XCTestCase {
    private func response(_ code: Int = 200, host: String = "rnwb.example.com", headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://\(host)/panel/api/overview")!, statusCode: code, httpVersion: nil, headerFields: headers)!
    }

    func testAccessRedirectHasActionableError() {
        let http = response(302, headers: ["Location": "https://team.cloudflareaccess.com/cdn-cgi/access/login"])
        XCTAssertThrowsError(try APIClient.validateResponse(http, data: Data())) {
            XCTAssertEqual($0 as? APIError, .cloudflareAccessRequired)
        }
    }

    func testFollowedAccessHTMLIsNotReportedAsJSONDecodingFailure() {
        let http = response(headers: ["Content-Type": "text/html"])
        let body = Data("<!doctype html><title>Cloudflare Access</title>".utf8)
        XCTAssertThrowsError(try APIClient.validateResponse(http, data: body)) {
            XCTAssertEqual($0 as? APIError, .cloudflareAccessRequired)
        }
    }

    func testUnexpectedHTMLAndWrongPanelKeyAreDifferentErrors() {
        XCTAssertThrowsError(try APIClient.validateResponse(response(headers: ["Content-Type": "text/html"]), data: Data("<html>Other website</html>".utf8))) {
            XCTAssertEqual($0 as? APIError, .unexpectedHTML)
        }
        XCTAssertThrowsError(try APIClient.validateResponse(response(401, headers: ["Content-Type": "application/json"]), data: Data("{}".utf8))) {
            XCTAssertEqual($0 as? APIError, .unauthorized)
        }
        XCTAssertNoThrow(try APIClient.validateResponse(response(headers: ["Content-Type": "application/json"]), data: Data("{}".utf8)))
    }

    private func cookie(domain: String = "rnwb.example.com", path: String = "/", expires: Date = Date().addingTimeInterval(3600), name: String = "CF_Authorization") -> HTTPCookie {
        HTTPCookie(properties: [.name: name, .value: "unit-test-only", .domain: domain, .path: path, .secure: "TRUE", .expires: expires])!
    }

    func testCookiesAreScopedByHTTPSHostPathAndExpiry() {
        let c = cookie(path: "/panel")
        XCTAssertTrue(AccessCookieBridge.eligible(c, for: URL(string: "https://rnwb.example.com/panel/api/overview")!))
        XCTAssertFalse(AccessCookieBridge.eligible(c, for: URL(string: "https://dmwb.example.com/panel/api/overview")!))
        XCTAssertFalse(AccessCookieBridge.eligible(c, for: URL(string: "https://rnwb.example.com.evil.test/panel")!))
        XCTAssertFalse(AccessCookieBridge.eligible(c, for: URL(string: "http://rnwb.example.com/panel")!))
        XCTAssertFalse(AccessCookieBridge.eligible(c, for: URL(string: "https://rnwb.example.com/panels")!))
        XCTAssertFalse(AccessCookieBridge.eligible(cookie(expires: Date().addingTimeInterval(-10)), for: URL(string: "https://rnwb.example.com/")!))
        XCTAssertFalse(AccessCookieBridge.eligible(cookie(name: "other_session"), for: URL(string: "https://rnwb.example.com/")!))
    }

    func testDomainCookieSuffixDoesNotMatchUnrelatedDomain() {
        let c = cookie(domain: ".example.com")
        XCTAssertTrue(AccessCookieBridge.eligible(c, for: URL(string: "https://rnwb.example.com/")!))
        XCTAssertFalse(AccessCookieBridge.eligible(c, for: URL(string: "https://badexample.com/")!))
    }

    func testAPIRedirectGuardDoesNotForwardBearerCredentials() {
        let guardDelegate = PanelRedirectGuard()
        var request = URLRequest(url: URL(string: "https://team.cloudflareaccess.com/")!)
        request.setValue("Bearer unit-test-only", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.dataTask(with: URL(string: "https://rnwb.example.com/")!)
        var callbackInvoked = false
        guardDelegate.urlSession(.shared, task: task, willPerformHTTPRedirection: response(302, headers: [:]), newRequest: request) { redirected in
            callbackInvoked = true
            XCTAssertNil(redirected)
        }
        XCTAssertTrue(callbackInvoked)
        task.cancel()
    }

    @MainActor
    func testPersistentWebKitCookieCanBridgeToMatchingAPIOnly() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let c = cookie(domain: "cf-auth-unit-test.invalid")
        await withCheckedContinuation { continuation in
            store.setCookie(c) { continuation.resume() }
        }
        let matching = await AccessCookieBridge.header(for: URL(string: "https://cf-auth-unit-test.invalid/panel/api/overview")!)
        let unrelated = await AccessCookieBridge.header(for: URL(string: "https://unrelated-unit-test.invalid/")!)
        XCTAssertNotNil(matching)
        XCTAssertNil(unrelated)
        await AccessCookieBridge.clear(for: URL(string: "https://cf-auth-unit-test.invalid/")!)
        let cleared = await AccessCookieBridge.header(for: URL(string: "https://cf-auth-unit-test.invalid/")!)
        XCTAssertNil(cleared)
    }
}

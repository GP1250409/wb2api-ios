import XCTest
@testable import WB2API

final class HubClientTests: XCTestCase {
    private var client: HubClient!
    private var session: URLSession!
    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        client = HubClient(baseURL: URL(string: "https://hub.example.com")!, token: "unit-test-hub-session", session: session)
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
    }
    override func tearDown() {
        session.invalidateAndCancel()
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
        super.tearDown()
    }
    private func stub(code: Int = 200, body: String) {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data(body.utf8))
        }
    }

    func testHubPasswordLoginUsesCorrectBodyAndNeverBearerOrOldSession() async throws {
        stub(body: "{\"ok\":true,\"token\":\"new-unit-test-session\"}")
        let token = try await client.login(password: "unit-test-password")
        XCTAssertEqual(token, "new-unit-test-session")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/panel/login")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Panel-Token"))
    }

    func testAccountReadUsesHubSessionAndCorrectRouteWithoutBearer() async throws {
        stub(body: "{\"accounts\":[{\"uid\":\"a\",\"tasksEnabled\":true,\"dailyTokensToday\":17}],\"usable\":1}")
        let response = try await client.accounts()
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/accounts")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Panel-Token"), "unit-test-hub-session")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(request.url?.query?.contains("realm=all") == true)
        XCTAssertEqual(response.field("accounts").arrayValue?.first?.field("tasksEnabled").boolValue, true)
        XCTAssertEqual(response.field("accounts").arrayValue?.first?.field("dailyTokensToday").intValue, 17)
    }

    func testWrongPasswordHasPasswordSpecificError() async {
        stub(code: 401, body: "{\"error\":{\"message\":\"invalid panel password\"}}")
        do { _ = try await client.login(password: "unit-test-password"); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? HubError, .invalidPassword) }
    }

    func testExpiredPanelSessionDoesNotPretendAPIKeyIsWrong() async {
        stub(code: 401, body: "{\"error\":{\"message\":\"panel password required\"}}")
        do { _ = try await client.accounts(); XCTFail("Expected expiration") }
        catch { XCTAssertEqual(error as? HubError, .sessionExpired) }
    }

    func testAccessRedirectStillRequiresCFLoginOnDM() async {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://team.cloudflareaccess.com/login"])!, Data())
        }
        do { _ = try await client.accounts(); XCTFail("Expected CF login") }
        catch { XCTAssertEqual(error as? APIError, .cloudflareAccessRequired) }
    }

    func testRejectedTaskIsNotReportedAsSuccess() async {
        stub(body: "{\"ok\":false,\"msg\":\"No participating accounts\"}")
        do { _ = try await client.perform("tasks/run", body: .object(["uid": .string("all")])); XCTFail("Expected task rejection") }
        catch { XCTAssertEqual(error as? HubError, .rejected("No participating accounts")) }
    }

    func testMalformedLoginDoesNotCreateConfiguredSession() async {
        stub(body: "{\"ok\":true}")
        do { _ = try await client.login(password: "unit-test-password"); XCTFail("Expected missing token") }
        catch { XCTAssertEqual(error as? HubError, .invalidLoginResponse) }
    }
}

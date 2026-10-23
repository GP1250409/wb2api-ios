import XCTest
@testable import WB2API

// MARK: - URLProtocol 桩

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - 客户端测试

final class APIClientTests: XCTestCase {
    private var client: APIClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        client = APIClient(baseURL: URL(string: "https://panel.example.com")!, apiKey: "test-key", session: session)
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
        super.tearDown()
    }

    private func stub(_ code: Int = 200, body: Data) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
    }

    func testSendsBearerTokenAndCorrectPath() async throws {
        stub(body: try Fixture.data("overview"))
        _ = try await client.overview()

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.url?.path, "/status")
    }

    func testQueryItemsAreAppended() async throws {
        stub(body: try Fixture.data("balance_history"))
        _ = try await client.balanceHistory(days: 7)
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        let comps = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        XCTAssertEqual(comps?.queryItems?.first(where: { $0.name == "days" })?.value, "7")
    }

    func testUnauthorizedMapsToUnauthorizedError() async throws {
        stub(401, body: Data("denied".utf8))
        do {
            _ = try await client.overview()
            XCTFail("应当抛错")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testServerErrorCarriesMessage() async throws {
        stub(500, body: Data("boom".utf8))
        do {
            _ = try await client.overview()
            XCTFail("应当抛错")
        } catch let error as APIError {
            guard case .http(let code, let msg) = error else {
                return XCTFail("应为 .http")
            }
            XCTAssertEqual(code, 500)
            XCTAssertEqual(msg, "boom")
        }
    }

    func testDecodingFailureIsReported() async throws {
        stub(body: Data("{\"unexpected\":true}".utf8))
        do {
            _ = try await client.status()
            XCTFail("应当抛错")
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("应为 .decoding，实际 \(error)") }
        }
    }

    func testPostActionPath() async throws {
        stub(body: Data("{\"ok\":true}".utf8))
        _ = try await client.accountAction("uid-1", action: "checkin")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/panel/api/accounts/uid-1/checkin")
    }

    func testMissingApiKeyOmitsHeader() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let anon = APIClient(baseURL: URL(string: "https://panel.example.com")!,
                             apiKey: "", session: URLSession(configuration: config))
        stub(body: try Fixture.data("overview"))
        _ = try await anon.overview()
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
}

import XCTest
@testable import WB2API

private final class DashboardRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [(String, String, Bool)] = []
    func append(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        records.append((request.httpMethod ?? "", request.url?.path ?? "", request.value(forHTTPHeaderField: "Authorization") == nil))
    }
    var snapshot: [(String, String, Bool)] {
        lock.lock(); defer { lock.unlock() }
        return records
    }
}

final class HubDashboardLoaderTests: XCTestCase {
    @MainActor func testDashboardReadsOnlyActualHubEndpointsAndKeepsWindow() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer {
            StubURLProtocol.handler = nil
            StubURLProtocol.lastRequest = nil
            session.invalidateAndCancel()
        }
        let health = try DashboardFixture.json("health")
        let accounts = try DashboardFixture.json("accounts")
        let analytics = try DashboardFixture.json("analytics")
        let series = try DashboardFixture.json("series")
        let log = DashboardRequestLog()
        StubURLProtocol.handler = { request in
            log.append(request)
            var response: JSONValue
            let path = request.url!.path
            switch path {
            case "/panel/status": response = .object(["authenticated": .bool(true)])
            case "/health": response = health
            case "/accounts": response = accounts
            case "/usage/analytics":
                let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let range = items.first { $0.name == "range" }?.value
                if range == "today" {
                    response = analytics.setting("window", .object(["since": .double(DashboardFixture.now.timeIntervalSince1970 - 3600), "until": .null]))
                } else { response = analytics }
            case "/usage/timeseries": response = series
            default: throw URLError(.unsupportedURL)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, try JSONEncoder().encode(response))
        }
        let client = HubClient(baseURL: URL(string: "https://hub-fixture.invalid")!, token: "unit-test-session", session: session)
        let model = HubDashboardModel()
        await model.loadOverview(client: client, now: DashboardFixture.now)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.warnings.isEmpty)
        XCTAssertEqual(model.overview?.ready, 4)
        XCTAssertEqual(model.overview?.today?.totals.totalTokens, 27194838)
        XCTAssertEqual(model.overview?.trend?.series?.count, 25)
        await model.loadUsage(client: client, range: .days7, now: DashboardFixture.now)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.usage?.window.range, .days7)
        XCTAssertEqual(model.usage?.snapshot.byAccount?.count, 5)
        let calls = log.snapshot
        XCTAssertTrue(calls.allSatisfy { $0.0 == "GET" })
        XCTAssertTrue(calls.allSatisfy { $0.2 })
        XCTAssertFalse(calls.contains { $0.1 == "/panel/api/overview" })
        XCTAssertEqual(calls.count, 6)
    }
}

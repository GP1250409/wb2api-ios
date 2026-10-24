import XCTest
import Combine
@testable import WB2API

/// iOS 16's ObservableObject does not automatically track nested Loaders.
final class CompatibilityStateTests: XCTestCase {
    @MainActor
    func testLoaderPublishesValueAndLoadingChanges() async {
        let loader = Loader<Int>()
        var notifications = 0
        let subscription = loader.objectWillChange.sink { notifications += 1 }
        await loader.load { 42 }
        XCTAssertEqual(loader.value, 42)
        XCTAssertFalse(loader.isLoading)
        XCTAssertGreaterThanOrEqual(notifications, 3)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testNestedLoaderNotificationsReachAllParentModels() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer {
            StubURLProtocol.handler = nil
            StubURLProtocol.lastRequest = nil
            session.invalidateAndCancel()
        }
        // All requests are intercepted. Never contacts a real server or account.
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data("compatibility-test".utf8))
        }
        let client = APIClient(baseURL: URL(string: "https://panel.example.com")!, apiKey: "", session: session)
        let overview = OverviewModel()
        let accounts = AccountsModel()
        let detail = AccountDetailModel()
        var counts = [0, 0, 0]
        let subscriptions = [
            overview.objectWillChange.sink { counts[0] += 1 },
            accounts.objectWillChange.sink { counts[1] += 1 },
            detail.objectWillChange.sink { counts[2] += 1 }
        ]
        await overview.load(using: client)
        await accounts.load(using: client)
        await detail.load(using: client)
        XCTAssertNotNil(overview.error)
        XCTAssertNotNil(accounts.error)
        XCTAssertNotNil(detail.error)
        XCTAssertTrue(counts.allSatisfy { $0 >= 2 }, "Nested loading/error changes must invalidate parent views: \(counts)")
        withExtendedLifetime(subscriptions) {}
    }
}

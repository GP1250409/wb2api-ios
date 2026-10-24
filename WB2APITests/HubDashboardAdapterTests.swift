import XCTest
@testable import WB2API

enum DashboardFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static func json(_ suffix: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: HubDashboardAdapterTests.self).url(forResource: "hub-dashboard-" + suffix, withExtension: "json"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    static func usage(range: UsageRange = .days7) throws -> HubUsagePresentation {
        var doc = try json("analytics")
        let window = HubUsageWindow(range: range, end: now)
        if range == .all { doc = doc.setting("window", .object(["since": .null, "until": .null])) }
        return try HubDashboardAdapter.usage(doc, window: window)
    }
    static func overview() throws -> HubOverviewPresentation {
        let today = try json("analytics").setting("window", .object(["since": .double(now.timeIntervalSince1970 - 3600), "until": .null]))
        return HubOverviewPresentation(health: try json("health"), accountsDocument: try json("accounts"), todayDocument: today,
            trend: try HubDashboardAdapter.trend(json("series"), since: now.timeIntervalSince1970 - 86400, until: now.timeIntervalSince1970))
    }
}

extension JSONValue {
    func setting(_ key: String, _ value: JSONValue) -> JSONValue {
        var object = objectValue ?? [:]
        object[key] = value
        return .object(object)
    }
}

final class HubDashboardAdapterTests: XCTestCase {
    func testRollingWindowIsCustomEpochsNotCalendarWeek() throws {
        let window = HubUsageWindow(range: .days7, end: DashboardFixture.now)
        let params = Dictionary(uniqueKeysWithValues: window.query.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(params["range"], "custom")
        XCTAssertEqual(params["realm"], "all")
        XCTAssertEqual(try XCTUnwrap(window.until) - XCTUnwrap(window.since), 168 * 3600)
        XCTAssertEqual(Double(params["since"] ?? ""), window.since)
    }
    func testBackendIgnoringRollingWindowIsRejected() throws {
        let raw = try DashboardFixture.json("analytics").setting("window", .object(["since": .null, "until": .null]))
        XCTAssertThrowsError(try HubDashboardAdapter.usage(raw, window: HubUsageWindow(range: .days7, end: DashboardFixture.now)))
    }
    func testAllTimeDoesNotInventThirtyDayDailyAverageOrSixtyDayCap() throws {
        let data = try DashboardFixture.usage(range: .all)
        XCTAssertEqual(data.perDay, "—")
        XCTAssertFalse(data.window.subtitle.contains("60"))
        XCTAssertNil(data.window.days)
        XCTAssertEqual(data.window.query.first { $0.name == "range" }?.value, "all")
    }
    func testRequestCountAndSuccessRateUseSuccessPlusErrors() throws {
        let data = try DashboardFixture.usage()
        XCTAssertEqual(data.snapshot.totals?.requests, 252)
        XCTAssertEqual(data.snapshot.totals?.errors, 2)
        XCTAssertEqual(try XCTUnwrap(data.stats.successRate), 250.0 / 252.0, accuracy: 0.000001)
    }
    func testLatencyUsesSamplesRatherThanTreatingMissingAsZero() throws {
        XCTAssertEqual(try DashboardFixture.usage().snapshot.totals?.avgLatencyMs, 15700)
        let absent = HubUsageStats(raw: .object(["elapsed_sum": .int(0), "elapsed_n": .int(0)]))
        XCTAssertNil(absent.averageLatency)
        XCTAssertNil(absent.cacheRate)
        XCTAssertNil(absent.requests)
        XCTAssertNil(absent.totals.totalTokens)
    }
    func testModelAndAccountGroupsUseSameWindowAndPreserveNicknames() throws {
        let data = try DashboardFixture.usage()
        XCTAssertEqual(data.snapshot.byAccount?.first?.displayName, "示例账号 1")
        XCTAssertEqual(data.snapshot.byModel?.first?.key, "deepseek-v4.1-flash")
        XCTAssertEqual(data.snapshot.byAccount?.compactMap(\.requests).reduce(0, +), data.snapshot.totals?.requests)
        XCTAssertEqual(data.snapshot.byRealm?.compactMap(\.requests).reduce(0, +), data.snapshot.totals?.requests)
        XCTAssertEqual(data.snapshot.byRealm?.count, 2)
    }
    func testCachePercentageAndTokenFormattingAreNotRawIntegers() throws {
        let data = try DashboardFixture.usage()
        XCTAssertEqual(try XCTUnwrap(data.stats.cacheRate), 26_333_588.0 / 27_008_808.0 * 100, accuracy: 0.000001)
        XCTAssertEqual(Fmt.tokens(data.snapshot.totals?.totalTokens), "27.2M")
        XCTAssertEqual(HubDashboardFormat.money(data.costCNY), "¥4.06")
        XCTAssertEqual(HubDashboardFormat.money(nil), "—")
    }
    func testPartialCreditCacheIsLabelledAsPartialNotAllAccounts() throws {
        let fixture = try DashboardFixture.json("accounts")
        var rows = try XCTUnwrap(fixture.field("accounts").arrayValue)
        rows[0] = rows[0].setting("credits", .null)
        let data = HubOverviewPresentation(health: try DashboardFixture.json("health"), accountsDocument: .object(["accounts": .array(rows)]), todayDocument: .null, trend: nil)
        XCTAssertEqual(data.creditCaption, "已知 4/5 个账号合计")
        XCTAssertEqual(data.credits, 23500)
        XCTAssertNil(data.today)
    }
    func testMissingAccountDetailsAndReadyCountRemainUnknown() {
        let data = HubOverviewPresentation(health: .object(["accounts": .int(5), "accounts_ready": .int(6)]), accountsDocument: .null, todayDocument: .null, trend: nil)
        XCTAssertNil(data.ready)
        XCTAssertNil(data.ratio)
        XCTAssertNil(data.credits)
        XCTAssertNil(data.paused)
        XCTAssertNil(data.cooldowns())
    }
    func testMissingFlagsAreNotClassifiedAsHealthy() {
        let data = HubOverviewPresentation(health: .null, accountsDocument: .object(["accounts": .array([.object(["uid": .string("fixture")])])]), todayDocument: .null, trend: nil)
        XCTAssertNil(data.cooling)
        XCTAssertNil(data.expired)
        XCTAssertNil(data.paused)
    }
    func testCooldownsReportOnlyAffectedAccountsNotInventedServableDenominator() throws {
        let data = try DashboardFixture.overview()
        let rows = try XCTUnwrap(data.cooldowns(now: DashboardFixture.now))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.affected, 1)
        XCTAssertEqual(rows.first?.model, "deepseek-v4.1-flash")
        XCTAssertEqual(rows.first?.realmLabel, "国内版")
    }
    func testTrendRetainsBothPartialBoundaryBucketsAndRealTokenSum() throws {
        let raw = try DashboardFixture.json("series")
        let data = try HubDashboardAdapter.trend(raw, since: DashboardFixture.now.timeIntervalSince1970 - 86400, until: DashboardFixture.now.timeIntervalSince1970)
        XCTAssertEqual(data.series?.count, 25)
        XCTAssertEqual(data.series?.compactMap(\.totalTokens).reduce(0, +), raw.field("series").arrayValue?.compactMap { $0.field("total_tokens").countNumber }.reduce(0, +))
    }
    func testMalformedTrendBucketIsNotReplacedWithZero() throws {
        var rows = try XCTUnwrap(DashboardFixture.json("series").field("series").arrayValue)
        rows[0] = rows[0].setting("total_tokens", .null)
        let raw = try DashboardFixture.json("series").setting("series", .array(rows))
        XCTAssertThrowsError(try HubDashboardAdapter.trend(raw, since: DashboardFixture.now.timeIntervalSince1970 - 86400, until: DashboardFixture.now.timeIntervalSince1970))
    }
    func testWrongTrendWindowIsRejected() throws {
        let raw = try DashboardFixture.json("series").setting("since", .int(0))
        XCTAssertThrowsError(try HubDashboardAdapter.trend(raw, since: DashboardFixture.now.timeIntervalSince1970 - 86400, until: DashboardFixture.now.timeIntervalSince1970))
    }
}

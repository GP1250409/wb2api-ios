import Foundation
import Combine

private struct HubDashboardRead: Sendable {
    let data: JSONValue
    let warning: String?
}

@MainActor
final class HubDashboardModel: ObservableObject {
    @Published private(set) var overview: HubOverviewPresentation?
    @Published private(set) var usage: HubUsagePresentation?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var warnings: [String] = []
    @Published private(set) var updated: Date?
    private var generation = UUID()

    private nonisolated static func read(_ label: String, operation: @Sendable () async throws -> JSONValue) async throws -> HubDashboardRead {
        do { return HubDashboardRead(data: try await operation(), warning: nil) }
        catch {
            if error.isCancellation { throw error }
            return HubDashboardRead(data: .null, warning: label + "：" + error.localizedDescription)
        }
    }

    func loadOverview(client: HubClient, now: Date = Date()) async {
        let ticket = UUID()
        generation = ticket
        isLoading = true
        error = nil
        defer { if generation == ticket { isLoading = false } }
        do {
            try await client.verifySession()
            let health = try await client.request("health")
            let hi = now.timeIntervalSince1970
            let lo = hi - 86400
            let seriesQuery = [URLQueryItem(name: "realm", value: "all"), URLQueryItem(name: "range", value: "custom"), URLQueryItem(name: "since", value: String(format: "%.3f", lo)), URLQueryItem(name: "until", value: String(format: "%.3f", hi)), URLQueryItem(name: "bucket", value: "3600")]
            async let accounts = Self.read("账号积分") { try await client.accounts() }
            async let today = Self.read("今日统计") {
                try await client.request("usage/analytics", query: [URLQueryItem(name: "realm", value: "all"), URLQueryItem(name: "range", value: "today")])
            }
            async let series = Self.read("小时趋势") { try await client.request("usage/timeseries", query: seriesQuery) }
            let values = try await (accounts, today, series)
            guard generation == ticket, !Task.isCancelled else { return }
            var notes = [values.0.warning, values.1.warning, values.2.warning].compactMap { $0 }
            var trend: UsageSnapshot?
            if values.2.warning == nil {
                do { trend = try HubDashboardAdapter.trend(values.2.data, since: lo, until: hi) }
                catch { notes.append(error.localizedDescription) }
            }
            let todayStart = values.1.data.field("window").field("since").finiteNumber
            let isToday = todayStart.map { $0 <= hi + 120 && hi - $0 <= 27 * 3600 } == true
                && values.1.data.field("summary").field("window").objectValue != nil
            if values.1.warning == nil && !isToday {
                notes.append("Hub 没有确认今日窗口，相关指标保留为空，避免拿全量数据冒充今日。")
            }
            overview = HubOverviewPresentation(health: health, accountsDocument: values.0.data, todayDocument: isToday ? values.1.data : .null, trend: trend)
            warnings = notes
            updated = Date()
        } catch {
            guard generation == ticket, !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    func loadUsage(client: HubClient, range: UsageRange, now: Date = Date()) async {
        let ticket = UUID()
        generation = ticket
        isLoading = true
        error = nil
        defer { if generation == ticket { isLoading = false } }
        let window = HubUsageWindow(range: range, end: now)
        do {
            let result = try await client.request("usage/analytics", query: window.query, timeout: 90)
            let presentation = try HubDashboardAdapter.usage(result, window: window)
            guard generation == ticket, !Task.isCancelled else { return }
            usage = presentation
            warnings = []
            updated = Date()
        } catch {
            guard generation == ticket, !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }
}

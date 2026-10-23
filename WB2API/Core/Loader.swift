import Foundation
import Observation

/// 通用加载器：统一 isLoading / error / value 三态，避免每个页面重写一遍。
@MainActor
@Observable
final class Loader<Value> {
    private(set) var value: Value?
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?

    var isEmpty: Bool { value == nil && error == nil }

    func load(_ operation: @escaping @MainActor () async throws -> Value) async {
        // 同一时刻只跑一轮：下拉刷新撞上进行中的自动刷新时不应并发重复请求
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            value = try await operation()
            error = nil
            lastUpdated = Date()
        } catch {
            // 下拉刷新 / 页面切换会取消进行中的请求，这不是真错误，别弹给用户
            guard !error.isCancellation else { return }
            // 已有数据时保留旧值，只更新错误提示（避免刷新失败把页面清空）
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func clearError() { error = nil }
}

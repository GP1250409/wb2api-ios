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
        isLoading = true
        defer { isLoading = false }
        do {
            value = try await operation()
            error = nil
            lastUpdated = Date()
        } catch is CancellationError {
            // 下拉刷新 / 页面切换会取消进行中的请求，不是真错误
        } catch let urlError as URLError where urlError.code == .cancelled {
            // 同上：URLSession 的取消错误不该弹给用户
        } catch {
            // 已有数据时保留旧值，只更新错误提示（避免刷新失败把页面清空）
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func clearError() { error = nil }
}

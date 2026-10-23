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
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func clearError() { error = nil }
}

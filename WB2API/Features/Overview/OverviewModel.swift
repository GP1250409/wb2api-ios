import Foundation
import Observation

/// 概览页的数据与操作。
///
/// 账号数据统一来自 `client.overview()`——公网 nginx 没有暴露 `/status`。
@MainActor
@Observable
final class OverviewModel {
    private let loader = Loader<OverviewResponse>()

    var toast: Toast?
    private(set) var runningBatch: BatchAction?

    var overview: OverviewResponse? { loader.value }
    var digest: OverviewDigest? { loader.value.map { OverviewDigest(overview: $0) } }
    var isLoading: Bool { loader.isLoading }
    var error: String? { loader.error }
    var lastUpdated: Date? { loader.lastUpdated }

    /// 概览只展示积分最高的前 5 个账号（顺序沿用面板返回顺序）。
    var previewAccounts: [Account] {
        Array((loader.value?.accounts ?? []).prefix(5))
    }

    // MARK: 读取

    func refreshIfStale(after interval: TimeInterval = 5, using client: APIClient?) async {
        if loader.isLoading { return }
        if let last = loader.lastUpdated, Date().timeIntervalSince(last) < interval { return }
        await load(using: client)
    }

    func load(using client: APIClient?) async {
        guard let client else {
            toast = Toast(kind: .failure, text: "尚未配置服务器地址")
            return
        }
        await loader.load { try await client.overview() }
    }

    // MARK: 批量操作

    func run(_ action: BatchAction, using client: APIClient?) async {
        guard runningBatch == nil else { return }
        guard let client else {
            toast = Toast(kind: .failure, text: "尚未配置服务器地址")
            return
        }

        runningBatch = action
        defer { runningBatch = nil }

        do {
            let outcome = ActionOutcome(try await client.batch(action.endpoint))
            guard outcome.ok else {
                toast = Toast(
                    kind: .failure,
                    text: "\(action.title)失败：\(outcome.message ?? "服务器拒绝了该操作")"
                )
                return
            }
            toast = Toast(kind: .success, text: outcome.message ?? "\(action.title)已提交")
            await load(using: client)
        } catch {
            toast = Toast(kind: .failure, text: "\(action.title)失败：\(error.humanMessage)")
        }
    }
}

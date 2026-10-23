import Foundation
import Observation

/// 账号列表的数据、筛选与单号操作。
@MainActor
@Observable
final class AccountsModel {
    private let loader = Loader<OverviewResponse>()

    var query = ""
    var filter: AccountFilter = .all
    var toast: Toast?
    private(set) var busyUIDs: Set<String> = []

    var accounts: [Account] { loader.value?.accounts ?? [] }
    var isLoading: Bool { loader.isLoading }
    var error: String? { loader.error }
    var lastUpdated: Date? { loader.lastUpdated }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 搜索 + 筛选后的结果，顺序沿用面板返回顺序。
    var filtered: [Account] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return accounts.filter { account in
            guard filter.matches(account) else { return false }
            guard !keyword.isEmpty else { return true }
            return account.displayName.localizedCaseInsensitiveContains(keyword)
                || account.uid.localizedCaseInsensitiveContains(keyword)
        }
    }

    var emptyTitle: String {
        filter == .all ? "还没有账号" : "没有符合条件的账号"
    }

    var emptyIcon: String { "person.2.slash" }

    var emptyMessage: String {
        filter == .all
            ? "在网页端登录 WorkBuddy 账号后，下拉刷新即可出现"
            : "换个筛选条件，或把筛选切回「全部」"
    }

    func count(for option: AccountFilter) -> Int {
        accounts.filter(option.matches).count
    }

    // MARK: 读取

    func refreshIfStale(after interval: TimeInterval = 3, using client: APIClient?) async {
        if loader.isLoading { return }
        if let last = loader.lastUpdated, Date().timeIntervalSince(last) < interval { return }
        await load(using: client)
    }

    /// - Parameter syncBalance: 用户主动刷新时为 true——先让后端查一轮上游余额，
    ///   否则面板缓存的积分不会变（后台余额刷新默认关闭）。
    func load(using client: APIClient?, syncBalance: Bool = false) async {
        guard let client else {
            toast = Toast(kind: .failure, text: "尚未配置服务器地址")
            return
        }
        if syncBalance {
            await BalanceSync.refreshAll(client: client)
        }
        await loader.load { try await client.overview() }
    }

    // MARK: 单号操作

    func perform(_ command: AccountCommand, on account: Account, using client: APIClient?) async {
        guard let client else {
            toast = Toast(kind: .failure, text: "尚未配置服务器地址")
            return
        }
        guard !busyUIDs.contains(account.uid) else { return }

        busyUIDs.insert(account.uid)
        defer { _ = busyUIDs.remove(account.uid) }

        do {
            let outcome = ActionOutcome(try await client.accountAction(account.uid, action: command.rawValue))
            guard outcome.ok else {
                toast = Toast(
                    kind: .failure,
                    text: "\(command.title)失败：\(outcome.message ?? "服务器拒绝了该操作")"
                )
                return
            }
            toast = Toast(
                kind: .success,
                text: outcome.message ?? "\(account.displayName) · \(command.title)已提交"
            )
            await load(using: client)
        } catch {
            toast = Toast(kind: .failure, text: "\(command.title)失败：\(error.humanMessage)")
        }
    }
}

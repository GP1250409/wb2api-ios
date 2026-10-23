import Foundation

extension TaskQueue {
    var isRunning: Bool { running ?? false }

    /// 排队总数：优先 `total`，缺失时退回 `items` 数量。
    var queuedCount: Int { total ?? items?.count ?? 0 }

    var stateText: String { isRunning ? "运行中" : "空闲" }
}

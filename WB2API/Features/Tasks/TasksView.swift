import SwiftUI

/// 任务：队列状态 + 批量操作 + 作业列表。页面可见时每 10 秒静默刷新队列。
struct TasksView: View {
    @Environment(SessionStore.self) private var session

    @State private var queue = Loader<TaskQueue>()
    @State private var jobs = Loader<JSONValue>()
    @State private var isScanning = false
    @State private var isRunning = false
    @State private var toast: Toast?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.m) {
                    if let message = queue.error ?? jobs.error {
                        ErrorBanner(message: message, retry: retry)
                    }

                    if isInitialLoading {
                        LoadingSkeleton(rows: 3)
                    } else {
                        QueueStatusCard(
                            running: queue.value?.isRunning ?? false,
                            total: queue.value?.queuedCount ?? 0,
                            concurrency: queue.value?.conc,
                            startedAt: queue.value?.startedAt
                        )
                        QueueActionsRow(
                            isScanning: isScanning,
                            isRunning: isRunning,
                            onScan: scanAll,
                            onRun: runQueue
                        )
                        JobListView(jobs: jobs.value)
                    }
                }
                .padding(.horizontal, Metrics.m)
                .padding(.vertical, Metrics.m)
            }
            .navigationTitle("任务")
            .refreshable { await refreshAll() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新", systemImage: "arrow.clockwise", action: refresh)
                        .labelStyle(.iconOnly)
                        .disabled(isScanning || isRunning)
                }
            }
            .task { await poll() }
            .toast($toast)
        }
    }

    private var isInitialLoading: Bool {
        queue.value == nil && queue.error == nil
    }

    // MARK: - 加载

    private func refresh() {
        Task { await refreshAll() }
    }

    private func retry() {
        Task { await refreshAll() }
    }

    private func refreshAll() async {
        guard let client = session.client() else { return }
        await queue.load { try await client.taskQueue() }
        await jobs.load { try await client.taskJobs() }
    }

    /// 队列状态随调度推进变化，页面可见时每 10 秒拉一次；`.task` 在页面消失时自动取消。
    private func poll() async {
        await refreshAll()
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
            await refreshAll()
        }
    }

    // MARK: - 批量操作

    private func scanAll() {
        Task {
            isScanning = true
            defer { isScanning = false }
            await runBatch("tasks/scan_all", title: "扫描全部", successText: "扫描已触发")
        }
    }

    private func runQueue() {
        Task {
            isRunning = true
            defer { isRunning = false }
            await runBatch("tasks/run_queue", title: "执行队列", successText: "队列已启动")
        }
    }

    private func runBatch(_ action: String, title: String, successText: String) async {
        guard let client = session.client() else {
            toast = Toast(kind: .failure, text: "尚未配置服务器地址")
            return
        }
        do {
            let outcome = ActionOutcome(try await client.batch(action))
            guard outcome.ok else {
                toast = Toast(
                    kind: .failure,
                    text: "\(title)失败：\(outcome.message ?? "服务器拒绝了该操作")"
                )
                return
            }
            toast = Toast(kind: .success, text: outcome.message ?? successText)
            await refreshAll()
        } catch {
            toast = Toast(kind: .failure, text: "\(title)失败：\(error.humanMessage)")
        }
    }
}

import SwiftUI

/// 任务：队列状态 + 批量操作 + 扫描结果（按账号逐项操作）+ 作业列表。
struct TasksView: View {
    @Environment(SessionStore.self) private var session

    @State private var queue = Loader<TaskQueue>()
    @State private var jobs = Loader<JSONValue>()
    @State private var scannedTasks: [AccountTask] = []
    @State private var busyTaskID: String?
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
                            onRun: runQueue,
                            onPause: pauseQueue
                        )
                        ScanResultView(tasks: scannedTasks) { task, action in
                            perform(action, on: task)
                        }
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

    // MARK: - 扫描与执行

    /// 扫描全部：把返回的任务明细存进 scannedTasks，用户逐项操作。
    /// （v2 之前的版本把结果扔了只弹 toast，表现为"没反应"。）
    private func scanAll() {
        Task {
            isScanning = true
            defer { isScanning = false }
            guard let client = session.client() else {
                toast = Toast(kind: .failure, text: "尚未配置服务器地址")
                return
            }
            do {
                let raw = try await client.scanAllTasks()
                let outcome = ActionOutcome(raw)
                guard outcome.ok else {
                    toast = Toast(kind: .failure, text: "扫描失败：\(outcome.message ?? "服务器拒绝")")
                    return
                }
                scannedTasks = AccountTaskParser.fromScan(raw)
                if scannedTasks.isEmpty {
                    toast = Toast(kind: .success, text: "扫描完成，暂无待办任务")
                } else {
                    let pending = raw.objectValue?["pending_count"]?.intValue ?? scannedTasks.count
                    toast = Toast(kind: .success, text: "扫描完成：\(pending) 项待办")
                }
                withAnimation(.snappy) { /* 列表入场 */ }
            } catch {
                toast = Toast(kind: .failure, text: "扫描失败：\(error.humanMessage)")
            }
        }
    }

    private func runQueue() {
        Task {
            isRunning = true
            defer { isRunning = false }
            await runBatch("tasks/run_queue", title: "执行队列", successText: "队列已启动")
        }
    }

    private func pauseQueue() {
        Task {
            await runBatch("tasks/pause", title: "暂停队列", successText: "暂停指令已发送")
        }
    }

    // MARK: - 单项操作

    private func perform(_ action: TaskAction, on task: AccountTask) {
        Task {
            busyTaskID = task.id
            defer { busyTaskID = nil }
            guard let client = session.client() else {
                toast = Toast(kind: .failure, text: "尚未配置服务器地址")
                return
            }
            do {
                let raw: JSONValue
                switch action {
                case .accept:
                    raw = try await client.acceptTasks(uid: task.uid, codes: [task.code])
                case .claim:
                    raw = try await client.claimTask(uid: task.uid, code: task.code)
                }
                let outcome = ActionOutcome(raw)
                // claim 有 already_claimed / credit 等字段，给出具体反馈
                var text = "\(task.title)\(action.rawValue)成功"
                if let credit = raw.objectValue?["credit"]?.intValue, credit > 0 {
                    text += "，+\(credit) 分"
                } else if raw.objectValue?["already_claimed"]?.boolValue == true {
                    text = "\(task.title)此前已领取"
                } else if let message = outcome.message {
                    text = message
                }
                toast = Toast(kind: outcome.ok ? .success : .failure, text: text)
                // 刷新该账号任务状态
                await refreshTasks(for: task)
            } catch {
                toast = Toast(kind: .failure, text: "\(action.rawValue)失败：\(error.humanMessage)")
            }
        }
    }

    /// 单号刷新任务状态并回填到 scannedTasks（避免整页重扫）。
    private func refreshTasks(for task: AccountTask) async {
        guard let client = session.client() else { return }
        do {
            let raw = try await client.accountTasks(uid: task.uid)
            let fresh = AccountTaskParser.fromSingle(raw, uid: task.uid, nickname: task.nickname, realm: task.realm)
            let staleIDs = Set(scannedTasks.filter { $0.uid == task.uid }.map(\.id))
            scannedTasks.removeAll { staleIDs.contains($0.id) }
            scannedTasks.append(contentsOf: fresh)
        } catch {
            // 静默失败：状态刷新不影响操作结果
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

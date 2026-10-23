import SwiftUI
import Foundation

/// 任务：队列状态、批量操作（扫描全部 / 执行队列）、任务作业列表。
struct TasksView: View {
    @Environment(SessionStore.self) private var session

    @State private var loader = Loader<TaskQueue>()
    @State private var jobsLoader = Loader<JSONValue>()
    @State private var runningAction: BatchAction?
    @State private var elapsed: Int = 0
    @State private var toast: Toast?

    private var client: APIClient? { session.client() }

    // MARK: - 批量动作

    private enum BatchAction: String, Identifiable, Hashable {
        case scanAll
        case runQueue

        var id: String { rawValue }

        var path: String {
            switch self {
            case .scanAll: return "tasks/scan_all"
            case .runQueue: return "tasks/run_queue"
            }
        }

        var title: String {
            switch self {
            case .scanAll: return "扫描全部"
            case .runQueue: return "执行队列"
            }
        }

        var icon: String {
            switch self {
            case .scanAll: return "magnifyingglass"
            case .runQueue: return "play.fill"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    if let message = loader.error {
                        ErrorBanner(message: message) {
                            Task { await refresh() }
                        }
                    }

                    if loader.value == nil && loader.isLoading {
                        SkeletonRows(count: 4)
                            .padding(.top, Spacing.m)
                    } else if let queue = loader.value {
                        queueSection(queue)
                    } else if loader.error == nil {
                        EmptyBox(
                            title: "暂无队列数据",
                            message: "下拉刷新重试",
                            systemImage: "checklist"
                        )
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }

                    actionsSection
                    jobsSection
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(Palette.background)
            .navigationTitle("任务")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新")
                    .disabled(loader.isLoading || runningAction != nil)
                }
            }
            .refreshable { await refresh() }
            .task { await refresh() }
            .toast($toast)
        }
    }

    // MARK: - 队列

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: Spacing.s),
            GridItem(.flexible(), spacing: Spacing.s)
        ]
    }

    private func queueSection(_ queue: TaskQueue) -> some View {
        let running = queue.running ?? false
        let started = queue.started ?? false
        return VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(
                title: "队列",
                subtitle: running ? "正在消费任务队列" : "队列当前空闲"
            )

            HStack(spacing: Spacing.s) {
                StatusPill(
                    text: running ? "运行中" : "空闲",
                    color: running ? Palette.success : Palette.textSecondary,
                    icon: running ? "circle.fill" : "pause.fill"
                )
                .symbolEffect(.pulse, options: .repeating, isActive: running)

                if started {
                    StatusPill(text: "已启动", color: Palette.accent, icon: "bolt.fill")
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.m)
            .motion(Motion.spring, value: running)

            LazyVGrid(columns: gridColumns, spacing: Spacing.s) {
                StatTile(
                    label: "运行",
                    value: running ? "是" : "否",
                    tint: running ? Palette.success : Palette.textSecondary,
                    caption: running ? "消费中" : "空闲"
                )
                StatTile(
                    label: "已启动",
                    value: started ? "是" : "否",
                    tint: started ? Palette.accent : Palette.textSecondary,
                    caption: started ? "已进入队列" : "未启动"
                )
                StatTile(
                    label: "任务总数",
                    value: Fmt.compact(queue.total),
                    caption: "条"
                )
                StatTile(
                    label: "并发",
                    value: queue.conc.map { String($0) } ?? "—",
                    caption: "槽位"
                )
            }
            .padding(.horizontal, Spacing.m)

            laneStrip(conc: queue.conc ?? 0, running: running)
                .padding(.horizontal, Spacing.m)

            HStack(spacing: Spacing.s) {
                Label("启动于 \(Fmt.clock(queue.startedAt))", systemImage: "clock")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
                if let seq = queue.seq {
                    Text("序号 \(seq)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.horizontal, Spacing.m)
        }
    }

    /// 并发槽位细条：运行时整条点亮，作为队列进度脉冲的签名细节。
    private func laneStrip(conc: Int, running: Bool) -> some View {
        let lanes = min(max(conc, 1), 12)
        return HStack(spacing: Spacing.xs) {
            ForEach(0..<lanes, id: \.self) { _ in
                Capsule()
                    .fill(running ? Palette.accent : Palette.divider)
                    .frame(height: 4)
            }
        }
        .motion(Motion.numeric, value: running)
        .accessibilityLabel("并发槽位")
        .accessibilityValue("\(conc)")
    }

    // MARK: - 操作

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "操作", subtitle: "对全部账号批量执行")

            HStack(spacing: Spacing.s) {
                actionButton(.scanAll, prominent: false)
                actionButton(.runQueue, prominent: true)
            }
            .padding(.horizontal, Spacing.m)

            if let action = runningAction {
                HStack(spacing: Spacing.s) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Palette.accent)
                    Text("正在执行「\(action.title)」· \(elapsed) 秒")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.m)
                .transition(.opacity)
            }
        }
        .motion(Motion.gentle, value: runningAction)
    }

    private func actionButton(_ action: BatchAction, prominent: Bool) -> some View {
        Button {
            Task { await perform(action) }
        } label: {
            HStack(spacing: Spacing.xs) {
                if runningAction == action {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(prominent ? Palette.surface : Palette.accent)
                } else {
                    Image(systemName: action.icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(action.title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: Hit.min)
            .foregroundStyle(prominent ? Palette.surface : Palette.accent)
            .background(
                prominent ? Palette.accent : Palette.accentSoft,
                in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(runningAction != nil)
        .opacity(runningAction == nil || runningAction == action ? 1 : 0.45)
    }

    // MARK: - 作业

    @ViewBuilder
    private var jobsSection: some View {
        SectionHeader(title: "任务作业", subtitle: jobsSubtitle)

        if jobsLoader.value == nil && jobsLoader.isLoading {
            SkeletonRows(count: 3)
        } else if let message = jobsLoader.error, jobsLoader.value == nil {
            ErrorBanner(message: message) {
                Task { await refreshJobs() }
            }
        } else if jobValues.isEmpty {
            EmptyBox(
                title: "暂无作业",
                message: "扫描或执行队列后会出现作业进度",
                systemImage: "square.stack.3d.up"
            )
            .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            VStack(spacing: Spacing.s) {
                ForEach(Array(jobValues.enumerated()), id: \.offset) { index, job in
                    jobRow(job)
                        .staggeredAppear(index: index)
                }
            }
            .padding(.horizontal, Spacing.m)
        }
    }

    private var jobsSubtitle: String {
        if jobsLoader.value == nil { return "读取中" }
        let count = jobValues.count
        return count == 0 ? "暂无进行中的作业" : "共 \(count) 条"
    }

    private var jobValues: [JSONValue] {
        guard let raw = jobsLoader.value else { return [] }
        if let array = raw.arrayValue { return array }
        if let object = raw.objectValue {
            for key in ["items", "jobs", "rows", "data"] {
                if let array = object[key]?.arrayValue { return array }
            }
        }
        return []
    }

    private func jobRow(_ job: JSONValue) -> some View {
        let title = jobTitle(job)
        let detail = jobDetail(job)
        let status = jobStatus(job)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(title)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let status {
                    StatusPill(text: status, color: jobStatusColor(status))
                }
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
    }

    /// 字段名未知：优先 name / title / kind / status，否则退回 displayText。
    private func jobTitle(_ job: JSONValue) -> String {
        if let object = job.objectValue {
            for key in ["name", "title", "kind", "status"] {
                if let value = object[key]?.stringValue,
                   !value.trimmingCharacters(in: .whitespaces).isEmpty {
                    return value
                }
            }
            if let first = scalarPairs(object).first {
                return "\(first.key) \(first.value)"
            }
            return "作业"
        }
        let text = job.displayText
        return text.isEmpty || text == "—" ? "作业" : text
    }

    private func jobDetail(_ job: JSONValue) -> String {
        guard let object = job.objectValue else { return "" }
        let parts = scalarPairs(object).prefix(4).map { "\($0.key) \($0.value)" }
        return parts.joined(separator: " · ")
    }

    private func jobStatus(_ job: JSONValue) -> String? {
        guard let object = job.objectValue else { return nil }
        for key in ["status", "state", "stage"] {
            if let value = object[key]?.stringValue, !value.isEmpty { return value }
        }
        return nil
    }

    private func jobStatusColor(_ status: String) -> Color {
        let text = status.lowercased()
        if text.contains("run") || text.contains("active") || text.contains("执行") { return Palette.accent }
        if text.contains("done") || text.contains("ok") || text.contains("success") || text.contains("完成") { return Palette.success }
        if text.contains("fail") || text.contains("error") || text.contains("失败") { return Palette.danger }
        if text.contains("wait") || text.contains("pending") || text.contains("idle") || text.contains("排队") { return Palette.warning }
        return Palette.textSecondary
    }

    private func scalarPairs(_ object: [String: JSONValue]) -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []
        for key in object.keys.sorted() {
            guard let value = object[key] else { continue }
            if value.objectValue != nil || value.arrayValue != nil { continue }
            result.append((key, value.displayText))
        }
        return result
    }

    // MARK: - 数据

    private func refresh() async {
        guard let client else { return }
        await loader.load { try await client.taskQueue() }
        await refreshJobs()
    }

    private func refreshJobs() async {
        guard let client else { return }
        await jobsLoader.load { try await client.taskJobs() }
    }

    private func perform(_ action: BatchAction) async {
        guard runningAction == nil else { return }
        guard let client else {
            toast = Toast(kind: .failure, text: "请先在设置中填写服务器地址与密钥")
            return
        }

        runningAction = action
        elapsed = 0

        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                elapsed += 1
            }
        }

        defer {
            ticker.cancel()
            runningAction = nil
        }

        do {
            let result = try await client.batch(action.path)
            toast = Toast(kind: .success, text: "\(action.title)已完成\(resultHint(result))")
            await refresh()
        } catch {
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            toast = Toast(kind: .failure, text: message)
        }
    }

    private func resultHint(_ value: JSONValue) -> String {
        if let object = value.objectValue {
            for key in ["message", "msg", "error", "detail"] {
                if let text = object[key]?.stringValue, !text.isEmpty {
                    return "：\(text)"
                }
            }
            if let count = object["count"]?.intValue {
                return "：\(count) 项"
            }
        }
        if let text = value.stringValue, !text.isEmpty {
            return "：\(text)"
        }
        return ""
    }
}

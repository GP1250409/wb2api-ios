import SwiftUI

/// 配置编辑：`client.config()` → 按顶层 key 分组渲染为原生控件，保存走 `client.saveConfig`。
///
/// 结构假设（与后端 config.json 对齐，见 WB2APITests/Fixtures/config.json）：
/// - 第 1 层 = Section（listen / pool / schedule …）；
/// - 第 2 层 = 叶子控件；若该层仍是对象（如 `pool.session_sticky`），再展开一个二级 Section；
/// - 第 3 层及更深 = 只读展示，提示去「高级」JSON 编辑里改；
/// - 数组一律渲染为逗号分隔 TextField（保存时按逗号拆回，纯数字数组保持 Int）；
/// - 密钥类字段照常显示（服务器返回已脱敏）。
struct ConfigView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    private var client: APIClient? { session.client() }

    @State private var loader = Loader<ConfigResponse>()
    /// 服务端返回的原始顶层配置（脏检测与重置的基准）。
    @State private var original: [String: JSONValue] = [:]
    /// 当前编辑中的顶层配置（保存时整体提交）。
    @State private var draft: [String: JSONValue] = [:]
    /// 外部整体替换 draft（高级应用 / 放弃修改）时自增，用来重建各输入行以同步文本。
    @State private var revision = 0
    @State private var toast: Toast?
    @State private var showAdvanced = false
    @State private var advancedText = ""
    @State private var advancedError: String?
    @State private var saving = false
    @State private var showSheetDiscardDialog = false
    @State private var showLeaveDialog = false

    private var isDirty: Bool { draft != original }

    var body: some View {
        Group {
            if let error = loader.error, loader.value == nil {
                ScrollView {
                    ErrorBanner(message: error) {
                        Task { await reload() }
                    }
                    .padding(Spacing.m)
                }
                .background(Palette.background)
            } else {
                form
            }
        }
        .navigationTitle("配置")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isDirty)
        .toolbar { toolbarContent }
        .refreshable { await reload() }
        .task {
            if loader.isEmpty { await reload() }
        }
        .toast($toast)
        .sheet(isPresented: $showAdvanced) {
            advancedSheet
        }
        .confirmationDialog(
            "有未保存的修改",
            isPresented: $showLeaveDialog,
            titleVisibility: .visible
        ) {
            Button("放弃修改并返回", role: .destructive) {
                draft = original
                dismiss()
            }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("离开后本次修改不会提交到服务器。")
        }
    }

    // MARK: - 表单

    private var form: some View {
        Form {
            if loader.isLoading && original.isEmpty {
                Section {
                    SkeletonRows(count: 5)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            } else if original.isEmpty {
                Section {
                    EmptyBox(title: "暂无配置", message: "服务端返回了空配置", systemImage: "slider.horizontal.3")
                }
            } else {
                ForEach(draft.keys.sorted(), id: \.self) { key in
                    topSection(key: key)
                }

                if isDirty {
                    Section {
                        Button(role: .destructive) {
                            draft = original
                            revision += 1
                        } label: {
                            Label("放弃修改", systemImage: "arrow.uturn.backward")
                        }
                    } footer: {
                        Text("有未保存的修改，点右上角「保存」提交到服务器。")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }

    /// 第 1 层：顶层 key → Section；值为对象时下钻一层，否则直接渲染叶子控件。
    @ViewBuilder
    private func topSection(key: String) -> some View {
        let value = draft[key] ?? .null
        if let fields = value.objectValue {
            Section {
                ForEach(fields.keys.sorted(), id: \.self) { childKey in
                    childRow(path: [key, childKey], value: fields[childKey] ?? .null)
                }
            } header: {
                Text(key)
            }
        } else {
            Section {
                leafRow(path: [key], value: value)
            } header: {
                Text(key)
            }
        }
    }

    /// 第 2 层：仍是对象 → 只读（已深于两层）；否则叶子控件。
    @ViewBuilder
    private func childRow(path: [String], value: JSONValue) -> some View {
        if value.objectValue != nil {
            deepRow(path: path, value: value)
        } else {
            leafRow(path: path, value: value)
        }
    }

    /// 深层（≥ 3 层）只读行。
    private func deepRow(path: [String], value: JSONValue) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            KeyValueRow(label: path.last ?? "", value: value.displayText)
            Text("嵌套结构，请在「高级」里编辑 JSON")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    // MARK: - 叶子控件分发

    @ViewBuilder
    private func leafRow(path: [String], value: JSONValue) -> some View {
        Group {
            switch value {
            case .bool:
                ConfigToggleRow(path: path, draft: $draft)
            case .int, .double:
                ConfigNumberRow(path: path, draft: $draft)
            case .array:
                ConfigArrayRow(path: path, draft: $draft)
            case .string:
                ConfigTextRow(path: path, draft: $draft)
            default:
                KeyValueRow(label: path.last ?? "", value: value.displayText)
            }
        }
        // 高级编辑整体替换 draft 后，重建输入行让 @State 文本重新从 draft 读取
        .id("\(revision)-\(path.joined(separator: "."))")
    }

    // MARK: - 路径读写

    fileprivate static func get(_ draft: [String: JSONValue], path: [String]) -> JSONValue {
        var node: JSONValue = .object(draft)
        for key in path {
            guard let next = node.objectValue?[key] else { return .null }
            node = next
        }
        return node
    }

    fileprivate static func set(_ draft: inout [String: JSONValue], path: [String], value: JSONValue) {
        guard let first = path.first else { return }
        if path.count == 1 {
            draft[first] = value
            return
        }
        var child = draft[first]?.objectValue ?? [:]
        set(&child, path: Array(path.dropFirst()), value: value)
        draft[first] = .object(child)
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isDirty {
                Button {
                    showLeaveDialog = true
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button("高级") { openAdvanced() }
                .font(.system(size: 14, weight: .medium))
        }
        ToolbarItem(placement: .topBarTrailing) {
            if saving {
                ProgressView().controlSize(.small)
            } else {
                Button("保存") {
                    Task { await save() }
                }
                .fontWeight(.semibold)
                .disabled(!isDirty)
            }
        }
    }

    // MARK: - 保存

    private func save() async {
        guard let client else {
            toast = Toast(kind: .failure, text: "服务器地址无效，请先在设置里填写")
            return
        }
        saving = true
        defer { saving = false }
        do {
            _ = try await client.saveConfig(.object(draft))
            toast = Toast(kind: .success, text: "配置已保存")
            original = draft
            revision += 1
            await reload(keepDraft: false)
        } catch {
            toast = Toast(
                kind: .failure,
                text: (error as? APIError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    // MARK: - 高级 JSON 编辑

    private func openAdvanced() {
        let source: JSONValue = .object(isDirty ? draft : original)
        if let data = try? JSONEncoder().encode(source),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            advancedText = text
        } else {
            advancedText = "{}"
        }
        advancedError = nil
        showAdvanced = true
    }

    private var advancedSheet: some View {
        NavigationStack {
            TextEditor(text: $advancedText)
                .font(.system(size: 13, design: .monospaced))
                .padding(Spacing.s)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                .padding(Spacing.m)
                .navigationTitle("高级编辑")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") {
                            if isDirty {
                                showSheetDiscardDialog = true
                            } else {
                                showAdvanced = false
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("应用") { applyAdvanced() }
                            .fontWeight(.semibold)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let advancedError {
                        ErrorBanner(message: advancedError)
                            .padding(.bottom, Spacing.s)
                    }
                }
                .confirmationDialog(
                    "有未应用的修改",
                    isPresented: $showSheetDiscardDialog,
                    titleVisibility: .visible
                ) {
                    Button("放弃修改并关闭", role: .destructive) {
                        showAdvanced = false
                    }
                    Button("继续编辑", role: .cancel) {}
                } message: {
                    Text("关闭后本次 JSON 编辑不会写入表单。")
                }
        }
        .presentationDetents([.large])
    }

    /// 先用 JSONSerialization 校验，通过后再转 JSONValue 写回 draft（保存仍走「保存」按钮）。
    private func applyAdvanced() {
        guard let data = advancedText.data(using: .utf8) else {
            advancedError = "无法读取输入内容"
            return
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            advancedError = "JSON 格式错误：\(error.localizedDescription)"
            return
        }
        do {
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            guard let object = decoded.objectValue else {
                advancedError = "顶层必须是 JSON 对象（{ … }）"
                return
            }
            draft = object
            revision += 1
            advancedError = nil
            toast = Toast(kind: .info, text: "已应用到表单，记得点「保存」提交")
            showAdvanced = false
        } catch {
            advancedError = "JSON 解析失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 加载

    private func reload(keepDraft: Bool = true) async {
        guard let client else { return }
        let previousDraft = draft
        await loader.load { try await client.config() }
        guard let object = loader.value?.config.objectValue else { return }
        original = object
        if keepDraft, !previousDraft.isEmpty {
            // 保留用户未保存的顶层编辑，同时补齐服务端新增的 key
            var merged = previousDraft.filter { object[$0.key] != nil }
            for (key, value) in object where merged[key] == nil {
                merged[key] = value
            }
            draft = merged
        } else {
            draft = object
        }
        revision += 1
    }
}

// MARK: - Bool → Toggle

private struct ConfigToggleRow: View {
    let path: [String]
    @Binding var draft: [String: JSONValue]

    private var isOn: Binding<Bool> {
        Binding(
            get: { ConfigView.get(draft, path: path).boolValue ?? false },
            set: { ConfigView.set(&draft, path: path, value: .bool($0)) }
        )
    }

    var body: some View {
        Toggle(path.last ?? "", isOn: isOn)
            .motion(Motion.spring, value: isOn.wrappedValue)
    }
}

// MARK: - Int / Double → Stepper（时长类）或数字 TextField

private struct ConfigNumberRow: View {
    let path: [String]
    @Binding var draft: [String: JSONValue]

    @State private var text = ""
    @FocusState private var focused: Bool

    private var name: String { path.last ?? "" }

    private var current: JSONValue { ConfigView.get(draft, path: path) }
    private var number: Double? { current.doubleValue }
    private var isInteger: Bool {
        if case .int = current { return true }
        return false
    }

    /// 命名里带时长语义的整数字段用 Stepper（步长 5），其余走键盘输入。
    private var useStepper: Bool {
        guard isInteger else { return false }
        let keywords = ["seconds", "minutes", "hours", "interval", "timeout", "threshold"]
        let lower = name.lowercased()
        return keywords.contains(where: { lower.contains($0) })
    }

    private var displayValue: String {
        guard let number else { return "" }
        return isInteger ? "\(Int(number))" : String(format: "%g", number)
    }

    var body: some View {
        if useStepper, let number = number {
            Stepper(
                value: Binding(
                    get: { number },
                    set: { newValue in
                        ConfigView.set(&draft, path: path, value: isInteger ? .int(Int(newValue)) : .double(newValue))
                    }
                ),
                in: 0...100_000,
                step: 5
            ) {
                HStack {
                    Text(name)
                    Spacer()
                    Text(isInteger ? "\(Int(number))" : String(format: "%g", number))
                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        } else {
            HStack {
                Text(name)
                Spacer(minLength: Spacing.s)
                TextField("值", text: $text)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: 160)
                    .focused($focused)
            }
            .onAppear { text = displayValue }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onSubmit { commit() }
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            ConfigView.set(&draft, path: path, value: isInteger ? .int(0) : .double(0))
            return
        }
        if isInteger, let int = Int(trimmed) {
            ConfigView.set(&draft, path: path, value: .int(int))
        } else if let double = Double(trimmed) {
            ConfigView.set(&draft, path: path, value: isInteger ? .int(Int(double)) : .double(double))
        } else {
            text = displayValue
        }
    }
}

// MARK: - String → TextField

private struct ConfigTextRow: View {
    let path: [String]
    @Binding var draft: [String: JSONValue]

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(path.last ?? "")
            Spacer(minLength: Spacing.s)
            TextField("值", text: $text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: 200)
                .focused($focused)
        }
        .onAppear { text = ConfigView.get(draft, path: path).stringValue ?? "" }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onSubmit { commit() }
    }

    private func commit() {
        ConfigView.set(&draft, path: path, value: .string(text))
    }
}

// MARK: - 数组 → 逗号分隔 TextField

private struct ConfigArrayRow: View {
    let path: [String]
    @Binding var draft: [String: JSONValue]

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack {
                Text(path.last ?? "")
                Spacer(minLength: Spacing.s)
                Text("逗号分隔")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            TextField("如 9, 21", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .focused($focused)
        }
        .onAppear {
            let items = ConfigView.get(draft, path: path).arrayValue ?? []
            text = items.map(\.displayText).joined(separator: ", ")
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onSubmit { commit() }
    }

    private func commit() {
        let parts = text
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let allInt = !parts.isEmpty && parts.allSatisfy { Int($0) != nil }
        var values: [JSONValue] = []
        for part in parts {
            if allInt, let int = Int(part) {
                values.append(.int(int))
            } else {
                values.append(.string(part))
            }
        }
        ConfigView.set(&draft, path: path, value: .array(values))
    }
}

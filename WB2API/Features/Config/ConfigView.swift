import SwiftUI

/// 配置：按顶层 key 分组的原生表单 + 高级 JSON 编辑。
struct ConfigView: View {
    @Environment(SessionStore.self) private var session
    @State private var editor = ConfigEditor()
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var isSaving = false
    @State private var isJSONPresented = false
    @State private var toast: Toast?

    var body: some View {
        Form {
            if let errorText {
                Section {
                    ErrorBanner(message: errorText, retry: retry)
                }
            }

            if isLoading && !editor.isLoaded {
                Section {
                    LoadingSkeleton(rows: 6)
                }
            } else if !editor.isLoaded {
                ContentUnavailableView {
                    Label("配置未加载", systemImage: "slider.horizontal.3")
                } description: {
                    Text("下拉刷新重新获取面板配置。")
                }
            } else {
                Section {
                    LabeledContent("配置文件", value: editor.path ?? "—")
                    LabeledContent("字段数", value: "\(editor.topLevelKeys.count) 组")
                    if editor.apiKeyEnvManaged {
                        Label("api_key 由环境变量托管", systemImage: "lock.shield")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("概览")
                }

                ForEach(editor.topLevelKeys, id: \.self) { key in
                    Section {
                        ForEach(editor.fields(in: key)) { field in
                            ConfigFieldView(field: field) { newValue in
                                editor.set(newValue, for: field)
                            }
                        }
                    } header: {
                        Text(key)
                    }
                }

                Section {
                    Button("高级 JSON 编辑", systemImage: "curlybraces", action: presentJSON)
                    Button("还原改动", systemImage: "arrow.uturn.backward", action: revert)
                        .disabled(!editor.isDirty)
                } footer: {
                    Text("数组、嵌套对象等复杂字段请在高级 JSON 编辑中修改。")
                }
            }
        }
        .navigationTitle("配置")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                        .accessibilityLabel("正在保存")
                } else {
                    Button("保存", action: save)
                        .disabled(!editor.isDirty)
                }
            }
        }
        .sheet(isPresented: $isJSONPresented) {
            AdvancedJSONView(editor: editor)
        }
        .toast($toast)
    }

    // MARK: - 动作

    private func load() async {
        guard let client = session.client() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.config()
            editor.load(response)
            errorText = nil
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func retry() {
        Task { await load() }
    }

    private func save() {
        Task { await performSave() }
    }

    private func performSave() async {
        guard let client = session.client() else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let result = try await client.saveConfig(editor.draft)
            editor.markSaved()
            toast = Toast(kind: .success, text: result.summary)
            await load()
        } catch {
            toast = Toast(kind: .failure, text: error.humanMessage)
        }
    }

    private func revert() {
        editor.revert()
        toast = Toast(kind: .info, text: "已还原为加载时的配置")
    }

    private func presentJSON() {
        isJSONPresented = true
    }
}

#Preview {
    NavigationStack {
        ConfigView()
    }
    .environment(SessionStore())
}

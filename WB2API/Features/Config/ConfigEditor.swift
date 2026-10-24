import Foundation
import Combine

/// 配置编辑状态：保存加载时的快照与可编辑草稿，提供路径级读写。
@MainActor
final class ConfigEditor: ObservableObject {
    @Published private(set) var original: JSONValue = .object([:])
    @Published var draft: JSONValue = .object([:])
    @Published private(set) var path: String?
    @Published private(set) var apiKeyEnvManaged = false
    @Published private(set) var isLoaded = false

    var isDirty: Bool { draft != original }

    var hasContent: Bool {
        !(draft.objectValue ?? [:]).isEmpty
    }

    var topLevelKeys: [String] {
        (draft.objectValue ?? [:]).keys.sorted()
    }

    func load(_ response: ConfigResponse) {
        let normalized: JSONValue = response.config.objectValue == nil
            ? .object([:])
            : response.config
        original = normalized
        draft = normalized
        path = response.path
        apiKeyEnvManaged = response.apiKeyEnvManaged ?? false
        isLoaded = true
    }

    /// 保存成功后把草稿当作新的基线。
    func markSaved() {
        original = draft
    }

    func revert() {
        draft = original
    }

    /// 某个顶层 key 下的可编辑字段；嵌套对象只展开一层，其余交给高级编辑。
    func fields(in key: String) -> [ConfigField] {
        guard let object = draft.objectValue, let raw = object[key] else { return [] }

        if let nested = raw.objectValue, !nested.isEmpty, nested.values.allSatisfy(Self.isScalar) {
            return nested.keys.sorted().map { child in
                ConfigField(key: child, path: [key, child], value: nested[child] ?? .null)
            }
        }

        return [ConfigField(key: key, path: [key], value: raw)]
    }

    func set(_ value: JSONValue, for field: ConfigField) {
        draft = Self.replacing(in: draft, path: field.path, value: value)
    }

    // MARK: - 纯函数

    private static func isScalar(_ value: JSONValue) -> Bool {
        switch value {
        case .object, .array: false
        default: true
        }
    }

    private static func replacing(in root: JSONValue, path: [String], value: JSONValue) -> JSONValue {
        guard let key = path.first else { return value }
        var object = root.objectValue ?? [:]
        let child = object[key] ?? .null
        object[key] = replacing(in: child, path: Array(path.dropFirst()), value: value)
        return .object(object)
    }
}

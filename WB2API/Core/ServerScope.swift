import SwiftUI

private struct ServerScopeKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var serverScope: UUID? {
        get { self[ServerScopeKey.self] }
        set { self[ServerScopeKey.self] = newValue }
    }
}

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            ServerSwitcher()
            Divider()
            Group {
                if session.isConfigured {
                    if session.backend == .hub, let client = session.hubClient() { HubMainView(client: client) }
                    else { MainTabsView() }
                } else {
                    SetupView()
                }
            }
            .environment(\.serverScope, session.revision)
            .id(session.revision)
        }
    }
}

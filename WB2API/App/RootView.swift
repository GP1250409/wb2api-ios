import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            ServerSwitcher()
            Divider()
            Group {
                if session.isConfigured {
                    if session.backend == .hub { HubMainView() }
                    else { MainTabsView() }
                } else {
                    SetupView()
                }
            }
            .id(session.revision)
        }
    }
}

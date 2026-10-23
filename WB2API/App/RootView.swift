import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.isConfigured {
            MainTabsView()
        } else {
            SetupView()
        }
    }
}

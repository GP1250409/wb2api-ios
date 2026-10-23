import SwiftUI

@main
struct WB2APIApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Accent.primary)
        }
    }
}

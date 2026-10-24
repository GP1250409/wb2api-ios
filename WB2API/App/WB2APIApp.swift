import SwiftUI

@main
struct WB2APIApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .tint(Accent.primary)
        }
    }
}

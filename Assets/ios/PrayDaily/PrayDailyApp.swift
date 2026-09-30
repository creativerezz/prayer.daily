import SwiftUI

@main struct PrayDailyApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MobileRoot(store: store)
                .tint(Color("Sage"))
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await store.tick(); await store.updateReminders() }
                    }
                }
        }
    }
}

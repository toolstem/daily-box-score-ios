import SwiftUI

@main
struct DailyBoxScoreApp: App {
    @StateObject private var feed = FeedService()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var switches: RemoteSwitches
    @StateObject private var store: StoreManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let switches = RemoteSwitches()
        _switches = StateObject(wrappedValue: switches)
        _store = StateObject(wrappedValue: StoreManager(switches: switches))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(feed)
                .environmentObject(favorites)
                .environmentObject(store)
                .environmentObject(switches)
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                    // The reminder toggle in Settings also manages this;
                    // this keeps the default ON state scheduled from first launch.
                    // It is a one-shot alarm, and the schedule check below
                    // replaces it with reminders for the mornings after
                    // game days.
                    if UserDefaults.standard.object(forKey: "dailyReminderEnabled") == nil {
                        NotificationManager.shared.scheduleDailyReminder()
                    }
                    Task {
                        await NotificationManager.shared.refreshReminders(using: feed)
                    }
                    // Side by side: a slow config fetch never delays
                    // reading what the user owns.
                    Task { await switches.refresh() }
                    Task {
                        await store.refreshEntitlements()
                        await store.loadProducts()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Back in the foreground: re-read the switches and
                    // what the user owns, so an expired or refunded
                    // pass locks again without a relaunch.
                    guard phase == .active else { return }
                    Task { await switches.refresh() }
                    Task { await store.refreshEntitlements() }
                }
        }
    }
}

import SwiftUI

@main
struct DailyBoxScoreApp: App {
    @StateObject private var feed = FeedService()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var store = StoreManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(feed)
                .environmentObject(favorites)
                .environmentObject(store)
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                    // The reminder toggle in Settings also manages this;
                    // this keeps the default ON state scheduled from first launch.
                    // It is a one-shot alarm, and the schedule check below
                    // cancels it when no games are scheduled today.
                    if UserDefaults.standard.object(forKey: "dailyReminderEnabled") == nil {
                        NotificationManager.shared.scheduleDailyReminder()
                    }
                    Task {
                        let hasGamesToday = await feed.gamesScheduledToday()
                        NotificationManager.shared.updateReminder(hasGamesToday: hasGamesToday)
                    }
                    Task {
                        await store.loadProducts()
                        await store.updatePurchasedProducts()
                    }
                }
        }
    }
}

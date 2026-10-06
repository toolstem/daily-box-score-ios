import Foundation
import UserNotifications

/// Schedules the daily "box scores are ready" morning notification.
class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private let requestID = "daily-box-score"

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    func scheduleDailyReminder() {
        var date = DateComponents()
        date.hour = 7
        date.minute = 30

        let content = UNMutableNotificationContent()
        content.title = "Today's box scores are ready"
        content.body = "Yesterday's complete box scores, in the classic agate style."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(
            identifier: requestID, content: content, trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancelDailyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestID])
    }

    func setDailyReminder(enabled: Bool) {
        if enabled {
            scheduleDailyReminder()
        } else {
            cancelDailyReminder()
        }
    }
}

import Foundation
import UserNotifications

/// The daily morning reminder.
///
/// It fires every morning after a game day, at the time the user picks,
/// whether or not the app was opened the day before. Whenever the app
/// opens it fetches a week of MLB schedule and puts one reminder on the
/// calendar for each morning after a game day, so the reminders keep
/// coming for days after the last time the app was opened. Mornings
/// with no game the day before get no reminder. The reminders are
/// one-shot alarms, never a repeating one, so nothing fires in the
/// offseason once the last scheduled morning has passed.
class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    static let enabledKey = "dailyReminderEnabled"
    static let hourKey = "dailyReminderHour"
    static let minuteKey = "dailyReminderMinute"

    /// Chosen reminder time. Defaults to 7:30 AM.
    var reminderHour: Int {
        UserDefaults.standard.object(forKey: Self.hourKey) as? Int ?? 7
    }

    var reminderMinute: Int {
        UserDefaults.standard.object(forKey: Self.minuteKey) as? Int ?? 30
    }

    var reminderEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    private func reminderContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Yesterday's box scores are ready"
        content.body = "Every game from yesterday, with the full box score."
        content.sound = .default
        return content
    }

    /// The next occurrence of the chosen time: today if it is still
    /// ahead, otherwise tomorrow.
    private func nextFireDate(hour: Int, minute: Int) -> DateComponents {
        let calendar = Calendar.current
        let now = Date()
        var fire = calendar.dateComponents([.year, .month, .day], from: now)
        fire.hour = hour
        fire.minute = minute
        if let fireDate = calendar.date(from: fire), fireDate <= now {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: fireDate) {
                return calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: tomorrow
                )
            }
        }
        return fire
    }

    /// Puts one reminder on the calendar for the next occurrence of the
    /// chosen time. Used on first launch and when the toggle is switched
    /// on, so a new user gets a reminder even before the first schedule
    /// check runs. The next check replaces it with the game-day batch.
    func scheduleDailyReminder(hour: Int? = nil, minute: Int? = nil) {
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: nextFireDate(
                hour: hour ?? reminderHour, minute: minute ?? reminderMinute
            ),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "daily-box-score-next",
            content: reminderContent(), trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Puts reminders on the calendar for the mornings after the given
    /// game dates, at the chosen time. Mornings that have already passed
    /// are skipped. Replaces all pending reminders first, so a re-check
    /// never leaves stale or duplicate reminders behind. The app only
    /// ever schedules these reminders, so removing all pending requests
    /// touches nothing else.
    func scheduleReminders(afterGameDates gameDates: Set<String>) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        guard reminderEnabled else { return }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let now = Date()
        for gameDate in gameDates {
            guard let day = formatter.date(from: gameDate),
                  let morning = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: morning)
            components.hour = reminderHour
            components.minute = reminderMinute
            guard let fireDate = calendar.date(from: components),
                  fireDate > now else { continue }
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components, repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "daily-box-score-\(formatter.string(from: morning))",
                content: reminderContent(), trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    /// Removes all pending reminders.
    func cancelDailyReminder() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Fetches the MLB schedule from yesterday through six days ahead
    /// and refreshes the reminders for the mornings after game days.
    /// A failed check leaves the pending reminders alone; never cancel
    /// on a network error.
    func refreshReminders(using feed: FeedService) async {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let end = calendar.date(byAdding: .day, value: 6, to: now) ?? now
        guard let gameDates = await feed.gameDates(from: start, to: end) else { return }
        scheduleReminders(afterGameDates: gameDates)
    }

    func setDailyReminder(enabled: Bool) {
        if enabled {
            scheduleDailyReminder()
        } else {
            cancelDailyReminder()
        }
    }
}

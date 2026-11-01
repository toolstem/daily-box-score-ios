import Foundation
import UserNotifications

/// The daily morning reminder.
///
/// It fires only when there is actually a new edition to announce.
/// Each time the app opens it checks today's MLB schedule: if games are
/// scheduled today, tomorrow morning has an edition, so it puts one
/// reminder on the calendar for the chosen time. If no games are
/// scheduled (an off day, or the offseason), it cancels any pending
/// reminder. The reminder is a one-shot alarm, never a repeating one,
/// so it stops on its own after the season ends instead of firing
/// every morning all winter.
class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private let requestID = "daily-box-score"

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
    /// chosen time. Replaces any pending reminder with the same ID.
    func scheduleDailyReminder(hour: Int? = nil, minute: Int? = nil) {
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: nextFireDate(
                hour: hour ?? reminderHour, minute: minute ?? reminderMinute
            ),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: requestID, content: reminderContent(), trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Puts one reminder on the calendar for tomorrow morning at the
    /// chosen time. Used after the schedule check: the reminder announces
    /// tomorrow's edition, never today's, so opening the app before the
    /// chosen time can never produce a same-day false alarm on a day
    /// that follows an off day.
    func scheduleTomorrowReminder() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        var components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        components.hour = reminderHour
        components.minute = reminderMinute
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components, repeats: false
        )
        let request = UNNotificationRequest(
            identifier: requestID, content: reminderContent(), trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func reminderContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Yesterday's box scores are ready"
        content.body = "Every game from yesterday, with the full box score."
        content.sound = .default
        return content
    }

    func cancelDailyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestID])
    }

    /// Call after checking today's MLB schedule.
    /// - hasGamesToday: true when games are scheduled today (so tomorrow
    ///   has an edition), false when none, nil when the check failed.
    ///   A failed check leaves the pending reminder alone; never cancel
    ///   on a network error.
    func updateReminder(hasGamesToday: Bool?) {
        guard reminderEnabled else {
            cancelDailyReminder()
            return
        }
        guard let hasGames = hasGamesToday else { return }
        if hasGames {
            scheduleTomorrowReminder()
        } else {
            cancelDailyReminder()
        }
    }

    func setDailyReminder(enabled: Bool) {
        if enabled {
            scheduleDailyReminder()
        } else {
            cancelDailyReminder()
        }
    }
}

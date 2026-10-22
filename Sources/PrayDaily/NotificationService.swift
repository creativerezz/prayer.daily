import Foundation
import UserNotifications

enum NotificationAccess { case notDetermined, denied, authorized }

@MainActor protocol ReminderScheduling {
    func access() async -> NotificationAccess
    func requestAccess() async throws -> Bool
    func replace(with reminders: [Reminder]) async throws
    func sendTest(sound: String) async throws
}

@MainActor final class SystemReminders: ReminderScheduling {
    private let center = UNUserNotificationCenter.current()
    func access() async -> NotificationAccess {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
    func requestAccess() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func replace(with reminders: [Reminder]) async throws {
        let pending = await center.pendingNotificationRequests()
        try Task.checkCancellation()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0 != "pray.daily-test" })
        for reminder in reminders {
            try Task.checkCancellation()
            if reminder.date > Date() { try await center.add(Self.request(for: reminder)) }
        }
    }
    func sendTest(sound: String) async throws {
        try await center.add(Self.request(for: Reminder(id: "pray.daily-test", title: "pray.daily test reminder",
            body: "Your notifications are working.", date: Date().addingTimeInterval(3), sound: sound)))
    }
    static func request(for reminder: Reminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        if reminder.sound == "Default" { content.sound = .default }
        else if reminder.sound != "Silent" { content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: reminder.sound + ".aiff")) }
        // Absolute UTC components preserve the intended instant through DST and travel.
        let calendar = PrayerClock.calendar(in: TimeZone(secondsFromGMT: 0)!)
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }
}

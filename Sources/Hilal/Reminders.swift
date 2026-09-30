import Foundation

struct Reminder: Equatable {
    let id: String
    let title: String
    let body: String
    let date: Date
    let sound: String
}

enum ReminderPlan {
    static func event(_ day: Day) -> String? {
        let h = day.date.hijri
        guard let d = Int(h.day) else { return nil }
        if h.month.number == 9 && [18, 20, 22].contains(d) { return "Laylatul Qadr tonight · night \(d + 1)" }
        if h.month.number == 10 && d == 1 { return "Eid al-Fitr" }
        if h.month.number == 12 && d == 10 { return "Eid al-Adha" }
        return nil
    }
    static func make(schedule: PrayerSchedule?, preferences: Preferences, now: Date) -> [Reminder] {
        guard let schedule, schedule.calculation == preferences.calculation else { return [] }
        var reminders: [Reminder] = []
        for day in schedule.days {
            for prayer in day.prayers {
                if preferences.alerts {
                    reminders.append(Reminder(
                        id: "\(day.date.gregorian.date)-\(prayer.name)",
                        title: "\(prayer.name) in \(preferences.lead) minutes",
                        body: "Prayer time is \(PrayerClock.time(prayer.date, in: preferences.zone, locationZone: schedule.zone)) · \(preferences.address)",
                        date: prayer.date.addingTimeInterval(-Double(preferences.lead * 60)), sound: preferences.sound))
                }
                if preferences.azanIsOn(prayer.name) {
                    reminders.append(Reminder(
                        id: "azan-\(day.date.gregorian.date)-\(prayer.name)",
                        title: prayer.name,
                        body: "It's time for \(prayer.name).",
                        date: prayer.date, sound: "Azan"))
                }
            }
            if preferences.holyDays, let event = event(day) {
                // Qadr is an evening observance. Eid remains a morning reminder.
                let when = day.time(day.date.hijri.month.number == 9 ? "Maghrib" : "Fajr")
                if let when {
                    reminders.append(Reminder(id: "holy-\(day.date.gregorian.date)", title: event,
                        body: "Calculated Hijri date. Confirm observance with your local community.", date: when, sound: preferences.sound))
                }
            }
        }
        return reminders.filter { $0.date > now }.sorted { $0.date < $1.date }
    }
}

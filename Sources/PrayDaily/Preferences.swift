import Foundation

struct Preferences: Codable, Equatable {
    var address = ""
    var latitude: Double?
    var longitude: Double?
    var method = 0
    var school = 0
    var timezone = "System"
    var alerts = false
    var lead = 15
    var sound = "Glass"
    var holyDays = false
    var hijriOffset = 0
    var fastingDate: String?
    /// Prayers that play the azan when they begin. Missing on older saves, which stay off.
    var azanPrayers: [String]?

    var hasReminders: Bool { alerts || holyDays || !(azanPrayers ?? []).isEmpty }
    func azanIsOn(_ prayer: String) -> Bool { azanPrayers?.contains(prayer) == true }

    var zone: TimeZone { timezone == "System" ? .current : TimeZone(identifier: timezone) ?? .current }
    var hasLocation: Bool {
        guard let latitude, let longitude else { return false }
        return latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
    var calculation: Calculation {
        Calculation(latitude: latitude, longitude: longitude, method: method, school: school, hijriOffset: hijriOffset)
    }
    struct Calculation: Codable, Equatable {
        let latitude: Double?
        let longitude: Double?
        let method: Int
        let school: Int
        let hijriOffset: Int
    }
}

enum PrayerClock {
    static func calendar(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
    static func dateKey(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar(in: zone)
        formatter.timeZone = zone
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter.string(from: date)
    }
    static func time(_ date: Date?, in zone: TimeZone, locationZone: TimeZone) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.calendar = calendar(in: zone)
        formatter.timeZone = zone
        formatter.dateFormat = dateKey(date, in: zone) == dateKey(date, in: locationZone) ? "h:mm a" : "h:mm a (MMM d)"
        return formatter.string(from: date)
    }
}

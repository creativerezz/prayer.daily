import Foundation

struct Method: Codable, Identifiable { let id: Int; let name: String }
struct Prayer: Identifiable, Codable { var id: String { name }; let name: String; let date: Date }
struct Day: Codable {
    let timings: [String: String]
    let date: Dates
    var meta: Meta? = nil
    struct Meta: Codable { let timezone: String }
    struct Dates: Codable { let hijri: Hijri; let gregorian: Gregorian }
    struct Gregorian: Codable { let date: String }
    struct Hijri: Codable {
        let day: String; let month: Month; let year: String
        struct Month: Codable { let number: Int; let en: String }
    }
    var prayers: [Prayer] { ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"].compactMap { name in time(name).map { Prayer(name: name, date: $0) } } }
    func time(_ name: String) -> Date? { timings[name].flatMap { ISO8601DateFormatter().date(from: $0) } }
}
struct Response: Decodable { let code: Int; let data: Day }

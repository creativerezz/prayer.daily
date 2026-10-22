import Foundation

struct PrayerSchedule: Codable {
    let calculation: Preferences.Calculation
    let timezone: String
    let days: [Day]
    let fetchedAt: Date
    var zone: TimeZone { TimeZone(identifier: timezone) ?? .current }
    func today(at date: Date) -> Day? { days.first { $0.date.gregorian.date == PrayerClock.dateKey(date, in: zone) } }
    func next(after date: Date) -> Prayer? {
        days.flatMap(\.prayers).filter { $0.date > date }.min { $0.date < $1.date }
    }
}

protocol PrayerLoading {
    func load(preferences: Preferences, now: Date) async throws -> PrayerSchedule
}

enum PrayerServiceError: LocalizedError {
    case noLocation, invalidResponse, missingTimes, rateLimited
    var errorDescription: String? {
        switch self {
        case .noLocation: return "Find your city or use device location before loading prayer times."
        case .invalidResponse: return "The prayer-time service returned an invalid response. Please retry."
        case .missingTimes: return "The service could not calculate all five prayers for this location and method. Try another calculation method."
        case .rateLimited: return "The prayer-time service is receiving too many requests. Please try again in a few minutes."
        }
    }
}

struct PrayerService: PrayerLoading {
    var session = URLSession.shared

    static func request(date: String, preferences: Preferences) throws -> URL {
        guard preferences.hasLocation, let latitude = preferences.latitude, let longitude = preferences.longitude else { throw PrayerServiceError.noLocation }
        var url = URLComponents(string: "https://api.aladhan.com/v1/timings/\(date)")!
        // Let the provider determine the geographic timezone. A display timezone must
        // never change the date/instant of a prayer at the chosen location.
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "method", value: String(preferences.method)),
            URLQueryItem(name: "school", value: String(preferences.school)),
            URLQueryItem(name: "iso8601", value: "true"),
            URLQueryItem(name: "calendarMethod", value: "HJCoSA"),
            URLQueryItem(name: "midnightMode", value: [0, 7].contains(preferences.method) ? "1" : "0")
        ]
        return url.url!
    }

    func load(preferences: Preferences, now: Date) async throws -> PrayerSchedule {
        let probeKey = PrayerClock.dateKey(now, in: .current)
        let probe = try await fetch(date: probeKey, preferences: preferences)
        guard let timezone = probe.meta?.timezone, let zone = TimeZone(identifier: timezone) else { throw PrayerServiceError.invalidResponse }
        let calendar = PrayerClock.calendar(in: zone)
        var raw: [String: Day] = [probeKey: probe]
        let offset = min(2, max(-2, preferences.hijriOffset))
        let needed = Set(0...6).union((0...6).map { $0 + offset }).sorted()
        var missing = needed.compactMap { dayOffset -> String? in
            let date = calendar.date(byAdding: .day, value: dayOffset, to: now)!
            let key = PrayerClock.dateKey(date, in: zone)
            return raw[key] == nil ? key : nil
        }
        while !missing.isEmpty {
            try Task.checkCancellation()
            let batch = Array(missing.prefix(4))
            let fetched = try await withThrowingTaskGroup(of: (String, Day).self, returning: [(String, Day)].self) { group in
                for key in batch {
                    group.addTask {
                        try Task.checkCancellation()
                        return (key, try await self.fetch(date: key, preferences: preferences))
                    }
                }
                var results: [(String, Day)] = []
                do {
                    for try await result in group { results.append(result) }
                } catch {
                    group.cancelAll()
                    throw error
                }
                return results
            }
            try Task.checkCancellation()
            for (key, day) in fetched { raw[key] = day }
            missing.removeFirst(batch.count)
        }
        let days = try (0...6).map { dayOffset -> Day in
            let date = calendar.date(byAdding: .day, value: dayOffset, to: now)!
            let shifted = calendar.date(byAdding: .day, value: offset, to: date)!
            guard let original = raw[PrayerClock.dateKey(date, in: zone)],
                  let hijri = raw[PrayerClock.dateKey(shifted, in: zone)]?.date.hijri else { throw PrayerServiceError.invalidResponse }
            // HJCoSA ignores the API adjustment parameter. Use the provider's calendar
            // for the adjacent date, retaining this day's original prayer instants.
            return Day(timings: original.timings, date: .init(hijri: hijri, gregorian: original.date.gregorian), meta: original.meta)
        }
        return PrayerSchedule(calculation: preferences.calculation, timezone: timezone, days: days, fetchedAt: now)
    }

    private func fetch(date: String, preferences: Preferences) async throws -> Day {
        var request = URLRequest(url: try Self.request(date: date, preferences: preferences))
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 429 { throw PrayerServiceError.rateLimited }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PrayerServiceError.invalidResponse }
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard result.code == 200, result.data.date.gregorian.date == date else { throw PrayerServiceError.invalidResponse }
        let day = result.data
        guard day.prayers.count == 5, day.time("Imsak") != nil, day.time("Sunrise") != nil else { throw PrayerServiceError.missingTimes }
        guard zip(day.prayers, day.prayers.dropFirst()).allSatisfy({ $0.date < $1.date }) else { throw PrayerServiceError.invalidResponse }
        return day
    }
}

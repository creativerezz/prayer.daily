import Foundation
import UserNotifications

private let utc = TimeZone(secondsFromGMT: 0)!
private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
private let testNow = instant("2026-09-26T08:00:00Z")
private func preferences() -> Preferences {
    var p = Preferences()
    p.address = "Test city"
    p.latitude = 34.0522
    p.longitude = -118.2437
    p.timezone = "UTC"
    return p
}
private func fixtureDay(_ date: Date, hijriDay: String = "18", month: Int = 9) -> Day {
    let calendar = PrayerClock.calendar(in: utc)
    let start = calendar.startOfDay(for: date)
    let hours = ["Imsak": 4, "Fajr": 5, "Sunrise": 6, "Dhuhr": 12, "Asr": 15, "Sunset": 18, "Maghrib": 19, "Isha": 20]
    let times = hours.mapValues { ISO8601DateFormatter().string(from: start.addingTimeInterval(Double($0 * 3600))) }
    return Day(timings: times, date: .init(hijri: .init(day: hijriDay, month: .init(number: month, en: "Test month"), year: "1448"), gregorian: .init(date: PrayerClock.dateKey(date, in: utc))), meta: .init(timezone: "UTC"))
}
private func fixtureSchedule(_ p: Preferences, now: Date = testNow) -> PrayerSchedule {
    PrayerSchedule(calculation: p.calculation, timezone: "UTC", days: (0...6).map {
        fixtureDay(now.addingTimeInterval(Double($0 * 86400)), hijriDay: String(18 + $0))
    }, fetchedAt: now)
}

private final class FakeLoader: PrayerLoading {
    var calls = 0
    var handler: ((Preferences, Date) async throws -> PrayerSchedule)?
    func load(preferences: Preferences, now: Date) async throws -> PrayerSchedule {
        calls += 1
        if let handler { return try await handler(preferences, now) }
        return fixtureSchedule(preferences, now: now)
    }
}
@MainActor private final class FakeReminders: ReminderScheduling {
    var status: NotificationAccess = .authorized
    var grant = true
    var requests = 0
    var replacements = 0
    var reminders: [Reminder] = []
    var testSounds: [String] = []
    var fail = false
    var replaceHandler: (([Reminder]) async -> Void)?
    func access() async -> NotificationAccess { status }
    func requestAccess() async throws -> Bool { requests += 1; status = grant ? .authorized : .denied; return grant }
    func replace(with reminders: [Reminder]) async throws {
        if fail { throw URLError(.unknown) }
        if let replaceHandler { await replaceHandler(reminders) }
        replacements += 1
        self.reminders = reminders
    }
    func sendTest(sound: String) async throws { testSounds.append(sound) }
}

private final class FixtureURLProtocol: URLProtocol {
    static var seen: [URL] = []
    static var malformed = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.seen.append(url)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "dd-MM-yyyy"
        let date = formatter.date(from: url.lastPathComponent)!
        let delta = Int(date.timeIntervalSince(instant("2026-09-26T00:00:00Z")) / 86400)
        // Simulate a 29-day month boundary without guessing a Hijri month length.
        let hDay = delta >= 2 ? delta - 1 : 28 + delta
        var day = fixtureDay(date, hijriDay: String(hDay), month: delta >= 2 ? 10 : 9)
        if Self.malformed { day = Day(timings: [:], date: day.date, meta: day.meta) }
        let dayJSON = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(day))
        let data = try! JSONSerialization.data(withJSONObject: ["code": 200, "data": dayJSON])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main @MainActor struct BehaviorTests {
    static var passed = 0
    static var suites: [String] = []
    static func check(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        precondition(condition(), message, file: file, line: line)
    }
    static func test(_ name: String, _ body: () async throws -> Void) async throws {
        try await body()
        passed += 1
        print("PASS: \(name)")
    }
    static func eventually(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        check(condition(), "Timed out waiting for settings to apply")
    }
    private static func makeStore(_ p: Preferences = preferences(), loader: FakeLoader = FakeLoader(), reminders: FakeReminders? = nil) -> (Store, UserDefaults) {
        let name = "pray.daily.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(try! JSONEncoder().encode(p), forKey: "preferences")
        let store = Store(defaults: defaults, service: loader, notifications: reminders ?? FakeReminders(), startAutomatically: false, now: testNow, debounceNanoseconds: 0)
        suites.append(name)
        return (store, defaults)
    }
    static func main() async throws {
        defer { for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) } }
        try await test("legacy preferences survive the rename and fasting migration") {
            let json = #"{"address":"Test","latitude":1,"longitude":2,"method":7,"school":1,"timezone":"UTC","alerts":true,"lead":30,"sound":"Ping","holyDays":true,"fasting":true,"hijriOffset":-2}"#.data(using: .utf8)!
            let p = try JSONDecoder().decode(Preferences.self, from: json)
            check(p.method == 7 && p.lead == 30 && p.holyDays && p.fastingDate == nil, "Legacy settings were lost")
        }
        try await test("all calculation settings reach requests; display timezone cannot move prayers") {
            var p = preferences(); p.method = 7; p.school = 1; p.timezone = "Pacific/Auckland"
            let url = try PrayerService.request(date: "26-09-2026", preferences: p)
            let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
            check(query["method"] == "7" && query["school"] == "1" && query["midnightMode"] == "1", "Calculation settings missing")
            check(query["timezonestring"] == nil && query["adjustment"] == nil && query["iso8601"] == "true", "Unsafe display/ignored adjustment sent")
            p.method = 2
            check(tryQuery(p)["midnightMode"] == "0", "Non-Jafari midnight mode incorrect")
        }
        try await test("Hijri adjustment crosses a month boundary without moving prayer times") {
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureURLProtocol.self]
            let service = PrayerService(session: URLSession(configuration: config))
            let p = preferences()
            let base = try await service.load(preferences: p, now: testNow)
            var adjusted = p; adjusted.hijriOffset = 2
            let shifted = try await service.load(preferences: adjusted, now: testNow)
            check(base.days[0].date.hijri.day == "28" && base.days[0].date.hijri.month.number == 9, "Base calendar wrong")
            check(shifted.days[0].date.hijri.day == "1" && shifted.days[0].date.hijri.month.number == 10, "Month rollover incorrect")
            check(base.days[0].timings == shifted.days[0].timings, "Adjustment changed prayer times")
            adjusted.hijriOffset = -2
            let earlier = try await service.load(preferences: adjusted, now: testNow)
            check(earlier.days[0].date.hijri.day == "26", "Negative adjustment ignored")
        }
        try await test("incomplete provider responses are rejected") {
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureURLProtocol.self]
            FixtureURLProtocol.malformed = true
            defer { FixtureURLProtocol.malformed = false }
            do { _ = try await PrayerService(session: URLSession(configuration: config)).load(preferences: preferences(), now: testNow); preconditionFailure("Accepted missing times") }
            catch { check(error is PrayerServiceError, "Unexpected validation error") }
        }
        try await test("method and Asr changes automatically persist and refresh") {
            let loader = FakeLoader(); let (store, defaults) = makeStore(loader: loader)
            await store.refresh()
            store.prefs.method = 2; store.prefs.school = 1
            await eventually { store.currentSchedule?.calculation.method == 2 && store.currentSchedule?.calculation.school == 1 }
            let saved = try JSONDecoder().decode(Preferences.self, from: defaults.data(forKey: "preferences")!)
            check(saved.method == 2 && saved.school == 1 && loader.calls >= 2, "Settings did not reach persistence and service")
        }
        try await test("sound and lead changes reschedule immediately without a network fetch") {
            let loader = FakeLoader(); let notifications = FakeReminders()
            var p = preferences(); p.alerts = true
            let (store, _) = makeStore(p, loader: loader, reminders: notifications)
            await store.refresh(); let calls = loader.calls
            store.prefs.sound = "Ping"; store.prefs.lead = 30
            await eventually { notifications.reminders.first?.sound == "Ping" && notifications.reminders.first?.title.contains("30 minutes") == true }
            check(loader.calls == calls, "Notification settings unnecessarily refetched prayer times")
            check(notifications.reminders.first!.date == instant("2026-09-26T11:30:00Z"), "Lead time was not applied")
            store.prefs.alerts = false
            await eventually { notifications.reminders.isEmpty }
        }
        try await test("overlapping reminder updates finish with the latest settings") {
            let n = FakeReminders(); var p = preferences(); p.alerts = true
            let (store, _) = makeStore(p, reminders: n); await store.refresh()
            var resume: CheckedContinuation<Void, Never>?
            n.replaceHandler = { plan in
                if plan.first?.sound == "Ping" { await withCheckedContinuation { resume = $0 } }
            }
            store.prefs.sound = "Ping"
            await eventually { resume != nil }
            store.prefs.sound = "Pop"
            resume!.resume()
            await eventually { n.reminders.first?.sound == "Pop" }
            check(n.reminders.allSatisfy { $0.sound == "Pop" }, "A stale notification add survived replacement")
        }
        try await test("display timezone changes formatting while retaining absolute times") {
            let loader = FakeLoader(); let (store, _) = makeStore(loader: loader)
            await store.refresh(); let original = store.next!.date; let before = store.time(original); let calls = loader.calls
            store.prefs.timezone = "Asia/Tokyo"
            check(store.next!.date == original && store.time(original) != before && loader.calls == calls, "Display timezone moved a prayer")
        }
        try await test("denied notification permission is explicit and schedules nothing") {
            let n = FakeReminders(); n.status = .notDetermined; n.grant = false
            let (store, _) = makeStore(reminders: n); await store.refresh()
            store.prefs.alerts = true
            await eventually { store.notificationStatus.contains("System Settings") }
            check(n.requests == 1 && n.reminders.isEmpty, "Denied reminders claimed to work")
            await store.testNotification()
            check(n.testSounds.isEmpty && store.notice!.contains("System Settings"), "Test bypassed denied permission")
        }
        try await test("rapid sound edits retain the notification permission request") {
            let n = FakeReminders(); n.status = .notDetermined
            let (store, _) = makeStore(reminders: n); await store.refresh()
            store.prefs.alerts = true; store.prefs.sound = "Pop"; store.prefs.lead = 20
            await eventually { n.requests == 1 && n.reminders.first?.sound == "Pop" }
            check(n.status == .authorized, "Rapid changes lost the permission request")
        }
        try await test("notification test uses selected sound") {
            var p = preferences(); p.sound = "Silent"
            let n = FakeReminders(); let (store, _) = makeStore(p, reminders: n)
            await store.testNotification()
            check(n.testSounds == ["Silent"], "Test did not honor selected sound")
        }
        try await test("scheduling failures remain visible") {
            let n = FakeReminders(); n.fail = true
            let (store, _) = makeStore(reminders: n); await store.refresh()
            check(store.notificationStatus.contains("Could not schedule"), "Scheduling failure was hidden")
        }
        try await test("failed refresh preserves valid times and pending reminders") {
            let loader = FakeLoader(); let n = FakeReminders()
            var p = preferences(); p.alerts = true
            let (store, _) = makeStore(p, loader: loader, reminders: n)
            await store.refresh(); let saved = n.reminders; let next = store.next?.date
            loader.handler = { _, _ in throw URLError(.notConnectedToInternet) }
            await store.refresh()
            check(store.next?.date == next && n.reminders == saved && store.error!.contains("saved times"), "Failed refresh destroyed valid schedule")
        }
        try await test("offline refresh retries after backoff, not on every timer tick") {
            let loader = FakeLoader(); loader.handler = { _, _ in throw URLError(.notConnectedToInternet) }
            let (store, _) = makeStore(loader: loader)
            await store.refresh(); let failedCalls = loader.calls
            await store.tick(at: testNow.addingTimeInterval(1))
            check(loader.calls == failedCalls, "Offline timer retried too soon")
            loader.handler = nil
            await store.tick(at: testNow.addingTimeInterval(301))
            check(loader.calls == failedCalls + 1 && store.today != nil, "Offline refresh did not recover")
        }
        try await test("cached schedule restores after relaunch") {
            let loader = FakeLoader(); let (store, defaults) = makeStore(loader: loader)
            await store.refresh()
            defaults.set(try JSONEncoder().encode(store.prefs), forKey: "preferences")
            let restored = Store(defaults: defaults, service: loader, notifications: FakeReminders(), startAutomatically: false, now: testNow)
            check(restored.today != nil && restored.next?.date == store.next?.date, "Cached times failed to restore")
        }
        try await test("old method responses cannot overwrite a newer choice") {
            let loader = FakeLoader()
            var continuation: CheckedContinuation<PrayerSchedule, Never>?
            loader.handler = { p, now in
                if p.method == 0 { return await withCheckedContinuation { continuation = $0 } }
                return fixtureSchedule(p, now: now)
            }
            let (store, _) = makeStore(loader: loader)
            let old = Task { await store.refresh() }
            await eventually { continuation != nil }
            store.prefs.method = 2
            await eventually { store.currentSchedule?.calculation.method == 2 }
            continuation!.resume(returning: fixtureSchedule(preferences()))
            await old.value
            check(store.currentSchedule?.calculation.method == 2 && !store.loading, "Stale request won the race")
        }
        try await test("changed calculation hides old times and removes old reminders on failure") {
            let loader = FakeLoader(); let n = FakeReminders()
            var p = preferences(); p.alerts = true
            let (store, _) = makeStore(p, loader: loader, reminders: n); await store.refresh()
            loader.handler = { _, _ in throw URLError(.notConnectedToInternet) }
            store.prefs.method = 7
            await eventually { store.error != nil && !store.loading && n.reminders.isEmpty }
            check(store.today == nil, "New method displayed previous method's times")
        }
        try await test("fasting expires on the location's next calendar day") {
            let (store, _) = makeStore(); await store.refresh(); store.setFasting(true)
            check(store.fastingToday, "Fasting toggle did not activate")
            await store.tick(at: testNow.addingTimeInterval(86400))
            check(!store.fastingToday && store.prefs.fastingDate == nil, "Fasting persisted into another day")
        }
        try await test("next prayer after Isha is tomorrow's Fajr") {
            let s = fixtureSchedule(preferences())
            let next = s.next(after: instant("2026-09-26T21:00:00Z"))!
            check(next.name == "Fajr" && next.date == instant("2026-09-27T05:00:00Z"), "Next-day Fajr was missed")
        }
        try await test("holy-day toggle schedules Qadr at Maghrib and Eid at Fajr") {
            var p = preferences(); p.holyDays = true
            let plan = ReminderPlan.make(schedule: fixtureSchedule(p), preferences: p, now: testNow)
            check(plan.count == 3 && plan.first!.date == instant("2026-09-26T19:00:00Z"), "Qadr reminders were scheduled at dawn")
            let eid = PrayerSchedule(calculation: p.calculation, timezone: "UTC", days: [fixtureDay(testNow.addingTimeInterval(86400), hijriDay: "1", month: 10)], fetchedAt: testNow)
            check(ReminderPlan.make(schedule: eid, preferences: p, now: testNow).first!.date == instant("2026-09-27T05:00:00Z"), "Eid reminder time wrong")
            p.holyDays = false
            check(ReminderPlan.make(schedule: eid, preferences: p, now: testNow).isEmpty, "Disabled holy days still scheduled")
        }
        try await test("notification triggers preserve absolute time and silent sound") {
            let date = instant("2026-11-01T13:00:00Z")
            let reminder = Reminder(id: "dst", title: "Fajr", body: "Test", date: date, sound: "Silent")
            let request = SystemReminders.request(for: reminder)
            let trigger = request.trigger as! UNCalendarNotificationTrigger
            check(trigger.dateComponents.timeZone == utc && trigger.dateComponents.hour == 13 && trigger.dateComponents.day == 1, "DST-sensitive trigger")
            check(request.content.sound == nil, "Silent notification has sound")
        }
        print("PASS: \(passed) behavior tests")
        if CommandLine.arguments.contains("--live") { try await liveChecks() }
    }
    static func tryQuery(_ p: Preferences) -> [String: String] {
        let url = try! PrayerService.request(date: "26-09-2026", preferences: p)
        return Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
    }
    static func liveChecks() async throws {
        let service = PrayerService()
        let now = instant("2026-09-26T19:00:00Z")
        let p = preferences()
        let base = try await service.load(preferences: p, now: now)
        check(base.days.count == 7 && base.days[0].prayers.count == 5, "Live schedule incomplete")
        var alternate = p; alternate.method = 2
        let isna = try await service.load(preferences: alternate, now: now)
        check(base.days[0].time("Maghrib") != isna.days[0].time("Maghrib"), "Method change had no live effect")
        alternate = p; alternate.school = 1
        let hanafi = try await service.load(preferences: alternate, now: now)
        check(hanafi.days[0].time("Asr")! > base.days[0].time("Asr")!, "Hanafi setting had no live effect")
        alternate = p; alternate.hijriOffset = 2
        let shifted = try await service.load(preferences: alternate, now: now)
        check(shifted.days[0].date.hijri.day == base.days[2].date.hijri.day && shifted.days[0].timings == base.days[0].timings, "Live Hijri adjustment failed")
        alternate = p; alternate.timezone = "Asia/Tokyo"
        let tokyo = try await service.load(preferences: alternate, now: now)
        check(tokyo.days[0].timings == base.days[0].timings, "Display timezone changed live prayer instants")
        print("PASS: live API — seven days, method, Hanafi Asr, Hijri adjustment, display timezone")
        let geocodingLoader = FakeLoader()
        let (geocodingStore, _) = makeStore(loader: geocodingLoader)
        await geocodingStore.findAddress("London, United Kingdom")
        check(geocodingStore.error == nil && abs(geocodingStore.prefs.latitude! - 51.5) < 0.5, "Live Apple city lookup failed")
        await eventually { !geocodingStore.loading }
        let lookups = geocodingLoader.calls
        await geocodingStore.findAddress("London, United Kingdom")
        await eventually { geocodingLoader.calls > lookups && !geocodingStore.loading }
        print("PASS: live Apple city lookup, automatic schedule refresh, and same-city retry")
    }
}

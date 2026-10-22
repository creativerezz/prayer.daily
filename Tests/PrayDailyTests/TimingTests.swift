import Foundation
@main struct TimingTests {
    static func main() { let t = TimingTests(); t.testTimezoneOffsetsRepresentSameInstant(); t.testJafariIftarUsesMaghribAfterSunset(); t.testInvalidTimesAreNotInvented(); t.testNextDayAndDSTOffsets(); print("PASS: 4 timing tests") }
    func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Expected equal: \(a), \(b)") }
    func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
    func XCTAssertNotNil<T>(_ value: T?) { precondition(value != nil) }
    func XCTAssertTrue(_ value: Bool) { precondition(value) }
    func testTimezoneOffsetsRepresentSameInstant() {
        let a = fixture(["Fajr": "2026-09-14T05:21:00-07:00"])
        let b = fixture(["Fajr": "2026-09-14T12:21:00+00:00"])
        XCTAssertNotNil(a.time("Fajr"))
        XCTAssertEqual(a.time("Fajr"), b.time("Fajr"))
    }
    func testJafariIftarUsesMaghribAfterSunset() {
        let day = fixture(["Sunset": "2026-09-14T19:01:00-07:00", "Maghrib": "2026-09-14T19:16:00-07:00"])
        XCTAssertEqual(day.time("Maghrib")!.timeIntervalSince(day.time("Sunset")!), 900)
        XCTAssertEqual(day.prayers.map(\.name), ["Maghrib"])
    }
    func testInvalidTimesAreNotInvented() {
        XCTAssertNil(fixture(["Fajr": "-----"]).time("Fajr"))
        XCTAssertTrue(fixture([:]).prayers.isEmpty)
    }
    func testNextDayAndDSTOffsets() {
        let day = fixture(["Isha": "2026-10-31T20:00:00-07:00", "Fajr": "2026-11-01T05:00:00-08:00"])
        XCTAssertEqual(day.time("Fajr")!.timeIntervalSince(day.time("Isha")!), 10 * 3600)
    }
    private func fixture(_ times: [String:String]) -> Day {
        Day(timings: times, date: .init(hijri: .init(day: "3", month: .init(number: 4, en: "Rabi"), year: "1448"), gregorian: .init(date: "14-09-2026")))
    }
}

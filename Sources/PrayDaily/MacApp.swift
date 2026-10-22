import AppKit
import SwiftUI

@main struct PrayDailyApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        MenuBarExtra {
            Dashboard(store: store)
        } label: {
            Image(systemName: "moon.stars")
            if let next = store.next {
                Text("\(next.name) \(store.countdown(next.date).dropLast(3))")
            } else {
                Text("pray.daily")
            }
        }.menuBarExtraStyle(.window)
        Window("pray.daily", id: "dashboard") { Dashboard(store: store) }.windowResizability(
            .contentSize
        ).defaultPosition(.center)
    }
}
private let ink = Color(
    nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.949, green: 0.941, blue: 0.906, alpha: 1)
            : NSColor(srgbRed: 0.161, green: 0.243, blue: 0.196, alpha: 1)
    })
private let sage = Color(
    nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.686, green: 0.800, blue: 0.682, alpha: 1)
            : NSColor(srgbRed: 0.286, green: 0.408, blue: 0.318, alpha: 1)
    })
private let paper = Color(
    nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.078, green: 0.137, blue: 0.110, alpha: 1)
            : NSColor(srgbRed: 0.969, green: 0.961, blue: 0.933, alpha: 1)
    })
private let lightSage = Color(red: 0.286, green: 0.408, blue: 0.318)
private let lightPaper = Color(red: 0.969, green: 0.961, blue: 0.933)

struct Dashboard: View {
    @ObservedObject var store: Store
    @Environment(\.openWindow) private var openWindow
    @State private var timezoneSearch = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill").font(.system(size: 25)).foregroundStyle(sage)
                VStack(alignment: .leading, spacing: 2) {
                    Text("pray.daily").font(.system(size: 27, weight: .medium, design: .serif))
                    Text("A MOMENT FOR WHAT MATTERS").font(.system(size: 8, weight: .semibold))
                        .tracking(1.3).foregroundStyle(sage)
                }
                Spacer()
                Menu {
                    Button("Open dashboard") {
                        openWindow(id: "dashboard")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    Button("Refresh times") { Task { await store.refresh() } }
                    Divider()
                    Button("Quit pray.daily") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }.menuStyle(.borderlessButton).frame(width: 25)
            }.padding(24)
            HStack(spacing: 5) {
                nav("Today", icon: "sun.max", index: 0)
                nav("Ramadan", icon: "moon", index: 1)
                nav("Settings", icon: "slider.horizontal.3", index: 2)
            }.padding(5).background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.tab == 2 {
                        settings
                    } else if store.today != nil {
                        if store.tab == 0 { today } else { ramadan }
                    } else {
                        onboarding
                    }
                    if store.loading {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(store.isLocating ? "Finding location…" : "Updating prayer times…")
                                .font(.caption)
                        }
                    }
                    if let error = store.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                        Button("Retry") { Task { await store.refresh() } }
                    }
                    if let notice = store.notice {
                        Text(notice).font(.caption).foregroundStyle(sage)
                    }
                }.padding(24)
            }.frame(height: 545)
            HStack {
                Circle().fill(store.today == nil ? Color.orange : sage).frame(width: 5, height: 5)
                Text(
                    store.prefs.method == 0
                        ? "JAFARI · ITHNA ASHARI" : "\(store.methodName.uppercased())"
                ).lineLimit(1)
                Spacer()
                Text(store.zone.abbreviation() ?? store.zone.identifier)
            }.font(.system(size: 9, weight: .medium)).tracking(0.7).foregroundStyle(sage).padding(
                .horizontal, 24
            ).padding(.vertical, 15).background(ink.opacity(0.035))
        }.frame(width: 410).foregroundStyle(ink).background(paper)
    }
    func nav(_ title: String, icon: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { store.tab = index }
        } label: {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium)).frame(
                maxWidth: .infinity
            ).padding(.vertical, 9).background(
                store.tab == index ? paper : Color.clear, in: RoundedRectangle(cornerRadius: 9)
            ).shadow(color: .black.opacity(store.tab == index ? 0.05 : 0), radius: 3, y: 1)
        }.buttonStyle(.plain)
    }
    var dateHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(store.prefs.address, systemImage: "location").lineLimit(1)
                Spacer()
                Text(weekday)
            }.font(.system(size: 11)).foregroundStyle(sage)
            if let h = store.today?.date.hijri {
                Text("\(h.day) \(h.month.en) \(h.year) AH").font(.system(size: 22, design: .serif))
            }
            Text(gregorian).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    var gregorian: String {
        let f = DateFormatter()
        f.calendar = PrayerClock.calendar(in: store.locationZone)
        f.timeZone = store.locationZone
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: store.now)
    }
    var weekday: String {
        let f = DateFormatter()
        f.calendar = PrayerClock.calendar(in: store.locationZone)
        f.timeZone = store.locationZone
        f.dateFormat = "EEEE"
        return f.string(from: store.now)
    }
    var today: some View {
        VStack(alignment: .leading, spacing: 20) {
            dateHeader
            if let next = store.next {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("YOUR NEXT PRAYER").tracking(1.7).font(
                            .system(size: 9, weight: .semibold))
                        Spacer()
                        Image(systemName: "sparkle")
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(next.name).font(.system(size: 33, design: .serif))
                        Spacer()
                        Text(store.time(next.date)).font(.system(size: 13))
                    }
                    Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
                    HStack(alignment: .firstTextBaseline) {
                        Text(store.countdown(next.date)).font(
                            .system(size: 36, weight: .light, design: .monospaced))
                        Spacer()
                        Text("REMAINING").font(.system(size: 8, weight: .medium)).tracking(1.2)
                    }
                }.padding(22).foregroundStyle(lightPaper).background(
                    lightSage.gradient, in: RoundedRectangle(cornerRadius: 20))
            }
            HStack {
                caption("TODAY’S PRAYERS")
                Spacer()
                Text(
                    "\(store.today?.prayers.filter { $0.date <= store.now }.count ?? 0) of 5 passed"
                ).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            VStack(spacing: 3) {
                ForEach(store.today?.prayers ?? []) { prayer in
                    let active = prayer.date == store.next?.date && prayer.name == store.next?.name
                    HStack(spacing: 12) {
                        Image(systemName: symbol(prayer.name)).font(.system(size: 17)).frame(
                            width: 23
                        ).foregroundStyle(sage)
                        Text(prayer.name).font(
                            .system(size: 14, weight: active ? .semibold : .regular))
                        if prayer.name == "Maghrib" && store.ramadan {
                            Text("IFTAR").font(.system(size: 8)).foregroundStyle(sage)
                        }
                        Spacer()
                        Text(store.time(prayer.date)).font(
                            .system(size: 13, weight: active ? .semibold : .regular)
                        ).monospacedDigit()
                        Image(
                            systemName: prayer.date <= store.now
                                ? "checkmark" : active ? "arrow.left" : "circle"
                        ).font(.system(size: 9)).frame(width: 12).foregroundStyle(
                            sage.opacity(active ? 1 : 0.45))
                    }.padding(.horizontal, 13).padding(.vertical, 12).background(
                        active ? sage.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10)
                    )
                }
            }
            HStack {
                Label("Sunrise", systemImage: "sunrise")
                Spacer()
                Text(store.time(store.today?.time("Sunrise")))
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    var ramadan: some View {
        VStack(alignment: .leading, spacing: 20) {
            dateHeader
            Text(store.ramadan ? "A month of reflection." : "Make space for reflection.").font(
                .system(size: 29, design: .serif))
            Toggle(
                "Track a fast today",
                isOn: Binding(get: { store.fastingToday }, set: { store.setFasting($0) })
            ).tint(sage)
            if store.ramadan || store.fastingToday {
                if let iftar = store.today?.time("Maghrib") {
                    VStack(alignment: .leading, spacing: 12) {
                        caption("UNTIL IFTAR")
                        Text(iftar > store.now ? store.countdown(iftar) : "Time to break your fast")
                            .font(.system(size: 30, design: .monospaced))
                        Text("Maghrib · \(store.time(iftar))").font(.subheadline)
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(
                        sage.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                }
            } else {
                Text(
                    "Ramadan tracking appears automatically during the calculated month of Ramadan. You can also track a voluntary fast."
                ).font(.subheadline).foregroundStyle(.secondary)
            }
            timeCard(
                "Imsak / Suhoor", subtitle: "Precautionary cutoff",
                time: store.today?.time("Imsak"), icon: "moon.zzz")
            timeCard(
                "Fajr", subtitle: "Dawn prayer", time: store.today?.time("Fajr"), icon: "sunrise")
            timeCard(
                "Iftar", subtitle: "At calculated Maghrib", time: store.today?.time("Maghrib"),
                icon: "sunset")
            caption("HOLY DAYS · NEXT 7 DAYS")
            let events = store.days.filter { store.event($0) != nil }
            if events.isEmpty {
                Text("No scheduled holy days this week.").font(.subheadline).foregroundStyle(
                    .secondary)
            }
            ForEach(events, id: \.date.gregorian.date) { day in
                Text("\(store.event(day) ?? "") · \(day.date.gregorian.date)").font(.subheadline)
            }
            Text(
                "Hijri dates are calculated and may differ from local moon sighting. Laylatul Qadr reminders mark the evenings before the 19th, 21st and 23rd."
            ).font(.caption).foregroundStyle(.secondary)
        }
    }
    var onboarding: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "sun.horizon").font(.system(size: 55, weight: .ultraLight))
                .foregroundStyle(sage).padding(.top, 25)
            Text("Your day,\nin prayer.").font(.system(size: 43, design: .serif))
            Text(
                "A quiet companion for your daily prayers. Set your location to begin with Shia Jafari calculation."
            ).font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
            locationFields
            Text(
                "Your location is sent to AlAdhan to calculate prayer times. Address lookup uses Apple’s geocoding service."
            ).font(.caption).foregroundStyle(.secondary)
        }
    }
    var locationFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("City, country or street address", text: $store.locationQuery).textFieldStyle(
                .roundedBorder
            ).onSubmit { Task { await store.findAddress(store.locationQuery) } }
            HStack {
                Button("Find location") { Task { await store.findAddress(store.locationQuery) } }
                    .buttonStyle(.borderedProminent).tint(sage).disabled(
                        store.loading
                            || store.locationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                    )
                Button {
                    store.locate()
                } label: {
                    Label("Use my location", systemImage: "location")
                }.buttonStyle(.bordered).disabled(store.loading)
            }
        }
    }
    var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Make it yours.").font(.system(size: 30, design: .serif))
            Text("Settings save automatically. Calculation changes update your prayer times.").font(
                .caption
            ).foregroundStyle(.secondary)
            caption("LOCATION")
            locationFields
            Divider()
            caption("CALCULATION & CALENDAR")
            Picker("Method", selection: $store.prefs.method) {
                ForEach(store.methods) { Text($0.name).tag($0.id) }
            }
            Picker("Asr convention", selection: $store.prefs.school) {
                Text("Standard / Shafi").tag(0)
                Text("Hanafi").tag(1)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Display timezone")
                TextField("Search city or timezone", text: $timezoneSearch)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        timezoneRow("System", title: "Follow system")
                        ForEach(timezoneMatches, id: \.self) { zone in
                            timezoneRow(zone, title: zone.replacingOccurrences(of: "_", with: " "))
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 150)
                .background(ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
            Stepper(
                "Hijri adjustment: \(store.prefs.hijriOffset) days",
                value: $store.prefs.hijriOffset, in: -2...2)
            Text(
                "Prayer times and calendar dates use the chosen location. This timezone changes how the times are displayed."
            ).font(.caption).foregroundStyle(.secondary)
            if store.prefs.method == 0 {
                Text(
                    "Jafari uses 16° Fajr, 4° Maghrib and 14° Isha. Confirm local observance and precautionary Imsak with your community."
                ).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            caption("NOTIFICATIONS")
            Toggle("Pre-prayer reminders", isOn: $store.prefs.alerts)
            ForEach(["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"], id: \.self) { prayer in
                azanToggle(prayer)
            }
            Text("Azan plays when each selected prayer begins, using the Azan tone.").font(.caption)
                .foregroundStyle(.secondary)
            Picker("Remind me", selection: $store.prefs.lead) {
                ForEach(10...30, id: \.self) { Text("\($0) minutes before").tag($0) }
            }
            Picker("Sound", selection: $store.prefs.sound) {
                ForEach(["Silent", "Default", "Glass", "Ping", "Pop"], id: \.self) {
                    Text($0).tag($0)
                }
            }
            Button("Preview sound") {
                if store.prefs.sound == "Default" {
                    NSSound.beep()
                } else if let url = Bundle.main.url(
                    forResource: store.prefs.sound, withExtension: "aiff")
                {
                    NSSound(contentsOf: url, byReference: false)?.play()
                }
            }.disabled(store.prefs.sound == "Silent")
            Toggle("Holy day reminders", isOn: $store.prefs.holyDays)
            Text(store.notificationStatus).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Test notification") { Task { await store.testNotification() } }
                Button("Refresh times") { Task { await store.refresh() } }.disabled(
                    store.loading || !store.prefs.hasLocation)
            }
            Text(
                "Seven days of reminders are scheduled ahead. Open pray.daily weekly to refresh. Internet access is required for new times."
            ).font(.caption).foregroundStyle(.secondary)
            Link(
                "Calculation source · AlAdhan",
                destination: URL(string: "https://aladhan.com/calculation-methods")!
            ).font(.caption)
        }.font(.system(size: 12)).tint(sage)
    }
    private var timezoneMatches: [String] {
        TimeZone.knownTimeZoneIdentifiers.filter {
            timezoneSearch.isEmpty
                || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(
                    timezoneSearch)
        }
    }
    private func timezoneRow(_ value: String, title: String) -> some View {
        Button {
            store.prefs.timezone = value
        } label: {
            HStack {
                Text(title)
                Spacer()
                if store.prefs.timezone == value { Image(systemName: "checkmark") }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    private func azanToggle(_ prayer: String) -> some View {
        Toggle(
            "\(prayer) azan",
            isOn: Binding(
                get: { store.prefs.azanIsOn(prayer) },
                set: { enabled in
                    var prayers = store.prefs.azanPrayers ?? []
                    if enabled {
                        if !prayers.contains(prayer) { prayers.append(prayer) }
                    } else {
                        prayers.removeAll { $0 == prayer }
                    }
                    store.prefs.azanPrayers = prayers
                }
            ))
    }
    func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(sage)
    }
    func symbol(_ name: String) -> String {
        switch name {
        case "Fajr": return "sunrise"
        case "Dhuhr": return "sun.max"
        case "Asr": return "sun.haze"
        case "Maghrib": return "sunset"
        default: return "moon.stars"
        }
    }
    func timeCard(_ title: String, subtitle: String, time: Date?, icon: String) -> some View {
        HStack {
            Image(systemName: icon).font(.title2).frame(width: 30).foregroundStyle(sage)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(store.time(time)).monospacedDigit().font(.subheadline)
        }.padding(14).background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

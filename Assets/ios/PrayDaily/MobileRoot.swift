import SwiftUI

struct MobileRoot: View {
    @ObservedObject var store: Store
    var body: some View {
        TabView {
            NavigationStack { TodayView(store: store) }
                .tabItem { Label("Today", systemImage: "sun.max") }
            NavigationStack { FastingView(store: store) }
                .tabItem { Label("Fasting", systemImage: "moon") }
            NavigationStack { MobileSettings(store: store) }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
    }
}

struct TodayView: View {
    @ObservedObject var store: Store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 10) {
                    Image("BrandMark").resizable().scaledToFit().frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 11)).accessibilityHidden(true)
                    Text("pray.daily").font(.system(.title2, design: .serif, weight: .medium))
                    Spacer()
                    if store.loading { ProgressView().accessibilityLabel("Updating prayer times") }
                }
                if let day = store.today {
                    DateHeading(store: store, day: day)
                    if let next = store.next { NextPrayerCard(store: store, prayer: next) }
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            sectionLabel("TODAY’S PRAYERS")
                            Spacer()
                            Text("\(day.prayers.filter { $0.date <= store.now }.count) of 5 passed").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 0) {
                            ForEach(day.prayers) { prayer in
                                let active = prayer.date == store.next?.date && prayer.name == store.next?.name
                                HStack(spacing: 14) {
                                    Image(systemName: symbol(prayer.name)).font(.title3).frame(width: 26).foregroundStyle(Color("Sage")).accessibilityHidden(true)
                                    Text(prayer.name).fontWeight(active ? .semibold : .regular)
                                    Spacer(minLength: 10)
                                    Text(store.time(prayer.date)).font(.subheadline).monospacedDigit()
                                    if prayer.date <= store.now { Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Passed") }
                                    else if active { Circle().fill(Color("Sage")).frame(width: 6, height: 6).accessibilityLabel("Next prayer") }
                                }
                                .padding(16)
                                .background(active ? Color("Sage").opacity(0.11) : .clear)
                                .accessibilityElement(children: .combine)
                                if prayer.id != day.prayers.last?.id { Divider().padding(.leading, 56) }
                            }
                        }.background(Color("Panel"), in: RoundedRectangle(cornerRadius: 22)).clipShape(RoundedRectangle(cornerRadius: 22))
                        HStack {
                            Label("Sunrise", systemImage: "sunrise")
                            Spacer()
                            Text(store.time(day.time("Sunrise")))
                        }.font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
                    }
                    Text(store.methodName).font(.caption).foregroundStyle(.secondary)
                    Text("Times shown in \(store.zone.identifier.replacingOccurrences(of: "_", with: " ")).")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "sun.horizon").font(.system(size: 60, weight: .ultraLight)).foregroundStyle(Color("Sage")).padding(.top, 28).accessibilityHidden(true)
                        Text("Your day,\nin prayer.").font(.system(.largeTitle, design: .serif, weight: .medium))
                        Text("A quiet companion for your daily prayers. Choose your location to begin.").font(.body).foregroundStyle(.secondary)
                    }
                    LocationControls(store: store)
                    Text("Jafari calculation is selected by default. You can change the method in Settings.").font(.footnote).foregroundStyle(.secondary)
                }
                StoreMessage(store: store)
            }.padding(24).frame(maxWidth: 620)
        }
        .frame(maxWidth: .infinity)
        .background(Color("Paper"))
        .foregroundStyle(Color("Ink"))
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { if store.prefs.hasLocation { await store.refresh() } }
    }
    private func symbol(_ name: String) -> String {
        switch name { case "Fajr": return "sunrise"; case "Dhuhr": return "sun.max"; case "Asr": return "sun.haze"; case "Maghrib": return "sunset"; default: return "moon.stars" }
    }
}

struct DateHeading: View {
    @ObservedObject var store: Store
    let day: Day
    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = PrayerClock.calendar(in: store.locationZone)
        formatter.timeZone = store.locationZone
        formatter.dateStyle = .full
        return formatter.string(from: store.now)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.prefs.address, systemImage: "location").font(.subheadline).foregroundStyle(Color("Sage"))
            Text("\(day.date.hijri.day) \(day.date.hijri.month.en) \(day.date.hijri.year) AH")
                .font(.system(.title2, design: .serif))
            Text(dateTitle)
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct NextPrayerCard: View {
    @ObservedObject var store: Store
    let prayer: Prayer
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("YOUR NEXT PRAYER").font(.caption2.weight(.semibold)).tracking(2); Spacer(); Image(systemName: "sparkle") }
            HStack(alignment: .firstTextBaseline) {
                Text(prayer.name).font(.system(.largeTitle, design: .serif))
                Spacer()
                Text(store.time(prayer.date)).font(.subheadline)
            }
            Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
            Text(store.countdown(prayer.date)).font(.system(.largeTitle, design: .monospaced, weight: .light)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            Text("UNTIL YOUR NEXT MOMENT OF PAUSE").font(.caption2).tracking(1.4)
        }
        .padding(24)
        .foregroundStyle(Color(red: 0.97, green: 0.96, blue: 0.91))
        .background(LinearGradient(colors: [Color(red: 0.29, green: 0.41, blue: 0.32), Color(red: 0.19, green: 0.30, blue: 0.23)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
        .accessibilityElement(children: .combine)
    }
}

struct FastingView: View {
    @ObservedObject var store: Store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let day = store.today {
                    DateHeading(store: store, day: day)
                    Text(store.ramadan ? "A month of\nreflection." : "Make space for\nreflection.").font(.system(.largeTitle, design: .serif))
                    Toggle("Track a fast today", isOn: Binding(get: { store.fastingToday }, set: store.setFasting))
                        .padding(18).background(Color("Panel"), in: RoundedRectangle(cornerRadius: 18))
                    if store.ramadan || store.fastingToday, let iftar = day.time("Maghrib") {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel("UNTIL IFTAR")
                            Text(iftar > store.now ? store.countdown(iftar) : "Time to break your fast")
                                .font(.system(.title, design: .monospaced)).minimumScaleFactor(0.6).lineLimit(1)
                            Text("Maghrib · \(store.time(iftar))").font(.subheadline)
                        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Color("Sage").opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
                    }
                    VStack(spacing: 0) {
                        fastingRow("Imsak / Suhoor", subtitle: "Precautionary cutoff", date: day.time("Imsak"), symbol: "moon.zzz")
                        Divider().padding(.horizontal, 18)
                        fastingRow("Fajr", subtitle: "Dawn prayer", date: day.time("Fajr"), symbol: "sunrise")
                        Divider().padding(.horizontal, 18)
                        fastingRow("Iftar", subtitle: "At calculated Maghrib", date: day.time("Maghrib"), symbol: "sunset")
                    }.background(Color("Panel"), in: RoundedRectangle(cornerRadius: 22))
                    sectionLabel("HOLY DAYS · NEXT SEVEN DAYS")
                    let events = store.days.filter { store.event($0) != nil }
                    if events.isEmpty { Text("No scheduled holy days this week.").foregroundStyle(.secondary) }
                    ForEach(events, id: \.date.gregorian.date) { eventDay in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.event(eventDay) ?? "").font(.headline)
                            Text(eventDay.date.gregorian.date).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Text("Hijri dates are calculated and may differ from local moon sighting. Confirm dates and prayer times with your community.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Your fasting companion", systemImage: "moon", description: Text("Choose a location in Today or Settings to see Suhoor and Iftar times."))
                }
                StoreMessage(store: store)
            }.padding(24).frame(maxWidth: 620)
        }.frame(maxWidth: .infinity).background(Color("Paper")).foregroundStyle(Color("Ink"))
            .navigationTitle("Fasting").navigationBarTitleDisplayMode(.inline)
    }
    private func fastingRow(_ title: String, subtitle: String, date: Date?, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color("Sage")).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) { Text(title); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Text(store.time(date)).font(.subheadline).monospacedDigit()
        }.padding(18).accessibilityElement(children: .combine)
    }
}

struct LocationControls: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("City, country or street address", text: $store.locationQuery)
                .textContentType(.addressCity).submitLabel(.search).textInputAutocapitalization(.words)
                .padding(14).background(Color("Panel"), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("locationQuery")
                .onSubmit { Task { await store.findAddress(store.locationQuery) } }
            Button { Task { await store.findAddress(store.locationQuery) } } label: {
                HStack { Text("Find location"); Spacer(); Image(systemName: "arrow.right") }.padding(.vertical, 6)
            }.buttonStyle(.borderedProminent).disabled(store.loading || store.locationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("findLocation")
            Button { store.locate() } label: { Label("Use my location", systemImage: "location") }
                .disabled(store.loading).frame(minHeight: 44)
            Text("Address lookup uses Apple. Your selected coordinates are sent to AlAdhan to calculate prayer times.")
                .font(.caption).foregroundStyle(.secondary)
            if store.isLocating { ProgressView("Finding location…") }
        }
    }
}

struct StoreMessage: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = store.error {
                Text(error).font(.footnote).foregroundStyle(.red)
                if store.prefs.hasLocation { Button("Retry") { Task { await store.refresh() } }.disabled(store.loading) }
            }
            if let notice = store.notice { Text(notice).font(.footnote).foregroundStyle(Color("Sage")) }
        }
    }
}

func sectionLabel(_ title: String) -> some View {
    Text(title).font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(Color("Sage"))
}

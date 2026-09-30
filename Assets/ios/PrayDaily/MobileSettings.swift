import AVFoundation
import SwiftUI
import UIKit

struct MobileSettings: View {
    @ObservedObject var store: Store
    @StateObject private var preview = SoundPreview()
    var body: some View {
        Form {
            Section {
                LocationControls(store: store)
            } header: {
                Text("Location")
            } footer: {
                Text("Settings save automatically. Calculation changes update your prayer times.")
            }
            Section("Calculation & calendar") {
                Picker("Method", selection: $store.prefs.method) {
                    ForEach(store.methods) { Text($0.name).tag($0.id) }
                }.pickerStyle(.navigationLink)
                Picker("Asr convention", selection: $store.prefs.school) {
                    Text("Standard / Shafi").tag(0)
                    Text("Hanafi").tag(1)
                }
                NavigationLink {
                    TimezonePicker(selection: $store.prefs.timezone)
                } label: {
                    LabeledContent(
                        "Display timezone",
                        value: store.prefs.timezone == "System"
                            ? "Follow system"
                            : store.prefs.timezone.replacingOccurrences(of: "_", with: " "))
                }
                Stepper(
                    "Hijri adjustment: \(store.prefs.hijriOffset) days",
                    value: $store.prefs.hijriOffset, in: -2...2)
                Text(
                    "Times and calendar dates follow your chosen location. Display timezone changes the clock display without moving prayer times."
                )
                .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Pre-prayer reminders", isOn: $store.prefs.alerts)
                Picker("Remind me", selection: $store.prefs.lead) {
                    ForEach(10...30, id: \.self) { Text("\($0) minutes before").tag($0) }
                }
                Picker("Sound", selection: $store.prefs.sound) {
                    ForEach(["Silent", "Default", "Glass", "Ping", "Pop"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                if ["Glass", "Ping", "Pop"].contains(store.prefs.sound) {
                    Button("Preview sound") { preview.play(store.prefs.sound) }
                }
                Toggle("Holy day reminders", isOn: $store.prefs.holyDays)
                Text(store.notificationStatus).font(.footnote).foregroundStyle(.secondary)
                Button("Test notification") { Task { await store.testNotification() } }
                Button("Open notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text(
                    "Seven days of reminders are scheduled ahead. Open pray.daily at least weekly to refresh them. Sound also follows your iPhone’s notification and Focus settings."
                )
            }
            Section {
                Button("Refresh prayer times") { Task { await store.refresh() } }.disabled(
                    store.loading || !store.prefs.hasLocation)
                if store.loading { ProgressView("Updating…") }
                StoreMessage(store: store)
            }
            Section("About") {
                HStack(spacing: 14) {
                    Image("BrandMark").resizable().frame(width: 48, height: 48).clipShape(
                        RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("pray.daily").font(.system(.title3, design: .serif))
                        Text("A moment for what matters.").font(.caption).foregroundStyle(
                            .secondary)
                    }
                }
                NavigationLink("Privacy & data") { PrivacyView() }
                Link(
                    "Calculation source · AlAdhan",
                    destination: URL(string: "https://aladhan.com/calculation-methods")!)
                Text(
                    "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))"
                )
                .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("made by Reza ❤")
                        .font(.system(.footnote, design: .serif))
                    HStack(spacing: 16) {
                        Link("rezajafar.com", destination: URL(string: "https://rezajafar.com")!)
                        Link("GitHub", destination: URL(string: "https://github.com/creativerezz")!)
                    }
                    .font(.caption)
                }
                .padding(.top, 8)
            }
        }.navigationTitle("Settings").scrollContentBackground(.hidden).background(Color("Paper"))
    }
}

struct TimezonePicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var zones: [String] {
        TimeZone.knownTimeZoneIdentifiers.filter {
            search.isEmpty
                || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(
                    search)
        }
    }
    var body: some View {
        List {
            choice("System", title: "Follow system")
            ForEach(zones, id: \.self) {
                choice($0, title: $0.replacingOccurrences(of: "_", with: " "))
            }
        }.searchable(text: $search, prompt: "Search city or timezone").navigationTitle(
            "Display timezone")
    }
    private func choice(_ value: String, title: String) -> some View {
        Button {
            selection = value
            dismiss()
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if selection == value { Image(systemName: "checkmark") }
            }
        }.accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("On your iPhone") {
                Text(
                    "Your preferences, chosen location, and the latest seven-day schedule are saved on this device. There is no account, advertising, or analytics SDK."
                )
            }
            Section("Location & prayer times") {
                Text(
                    "Searching a city or address sends that query to Apple’s geocoding service. Choosing Use my location requests your device’s location only when you ask, after iOS permission."
                )
                Text(
                    "Your chosen latitude and longitude, calculation method, and Asr convention are sent to AlAdhan over HTTPS to obtain prayer times. AlAdhan’s handling of those requests is governed by its terms."
                )
                Link(
                    "AlAdhan terms",
                    destination: URL(string: "https://aladhan.com/credits-and-terms")!)
            }
            Section("Reminders") {
                Text(
                    "Prayer reminders are scheduled locally through iOS. You can turn reminders off in Settings and revoke notification or location access in the iPhone Settings app."
                )
            }
        }.navigationTitle("Privacy & data")
    }
}

@MainActor final class SoundPreview: ObservableObject {
    private var player: AVAudioPlayer?
    func play(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "aiff") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

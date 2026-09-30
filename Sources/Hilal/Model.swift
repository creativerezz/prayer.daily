import Foundation
import SwiftUI
import CoreLocation
import UserNotifications

@MainActor final class Store: NSObject, ObservableObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    @Published var tab = 0
    @Published var locationQuery = ""
    @Published var prefs: Preferences { didSet { settingsChanged(from: oldValue) } }
    @Published private(set) var schedule: PrayerSchedule?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLocating = false
    @Published var error: String?
    @Published var notice: String?
    @Published private(set) var notificationStatus = "Checking notification permission…"
    @Published var now: Date
    let methods: [Method]
    private let defaults: UserDefaults
    private let service: any PrayerLoading
    private let notifications: any ReminderScheduling
    private let debounceNanoseconds: UInt64
    private let location = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var waitingForLocationAuthorization = false
    private var timer: Timer?
    private var generation = 0
    private var refreshTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var pendingPermissionRequest = false
    private var nextRetry = Date.distantPast
    private var observedSystemZone = TimeZone.current.identifier

    var loading: Bool { isRefreshing || isLocating }
    var zone: TimeZone { prefs.zone }
    var locationZone: TimeZone { currentSchedule?.zone ?? .current }
    var currentSchedule: PrayerSchedule? { schedule?.calculation == prefs.calculation ? schedule : nil }
    var days: [Day] { currentSchedule?.days ?? [] }
    var today: Day? { currentSchedule?.today(at: now) }
    var next: Prayer? { currentSchedule?.next(after: now) }
    var ramadan: Bool { today?.date.hijri.month.number == 9 }
    var fastingToday: Bool { prefs.fastingDate == dateKey(now) }
    var methodName: String { methods.first { $0.id == prefs.method }?.name ?? "Selected method" }

    init(defaults: UserDefaults = .standard, service: any PrayerLoading = PrayerService(),
         notifications: any ReminderScheduling, methods: [Method]? = nil,
         startAutomatically: Bool = true, now: Date = Date(), debounceNanoseconds: UInt64 = 350_000_000) {
        self.defaults = defaults
        self.service = service
        self.notifications = notifications
        self.now = now
        self.debounceNanoseconds = debounceNanoseconds
        prefs = defaults.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        schedule = defaults.data(forKey: "prayerSchedule").flatMap { try? JSONDecoder().decode(PrayerSchedule.self, from: $0) }
        if let methods { self.methods = methods }
        else {
            #if SWIFT_PACKAGE
            let resourceBundle = Bundle.module
            #else
            let resourceBundle = Bundle.main
            #endif
            self.methods = resourceBundle.url(forResource: "methods", withExtension: "json")
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? JSONDecoder().decode([Method].self, from: $0) } ?? []
        }
        super.init()
        locationQuery = prefs.address
        location.delegate = self
        if startAutomatically {
            UNUserNotificationCenter.current().delegate = self
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.tick() }
            }
            Task { [weak self] in
                guard let self else { return }
                await self.updateReminders()
                if self.prefs.hasLocation { await self.refresh() }
            }
        }
    }
    convenience override init() { self.init(notifications: SystemReminders()) }

    private var systemSettings: String {
        #if os(iOS)
        return "Settings"
        #else
        return "System Settings"
        #endif
    }

    func dateKey(_ date: Date) -> String { PrayerClock.dateKey(date, in: locationZone) }
    func time(_ date: Date?) -> String { PrayerClock.time(date, in: zone, locationZone: locationZone) }
    func countdown(_ date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
    func setFasting(_ enabled: Bool) { prefs.fastingDate = enabled ? dateKey(now) : nil }
    func event(_ day: Day) -> String? { ReminderPlan.event(day) }

    private func save() {
        if let data = try? JSONEncoder().encode(prefs) { defaults.set(data, forKey: "preferences") }
    }
    private func settingsChanged(from previous: Preferences) {
        guard previous != prefs else { return }
        save()
        notice = nil
        if previous.calculation != prefs.calculation {
            generation += 1 // Reject responses from a previous location or method immediately.
            refreshTask?.cancel()
            error = nil
            isRefreshing = prefs.hasLocation
            enqueueReminders() // Remove reminders that belong to the previous calculation.
            refreshTask = Task { [weak self] in
                guard let self else { return }
                do { try await Task.sleep(nanoseconds: self.debounceNanoseconds) }
                catch { return }
                await self.refresh()
            }
        } else if previous.alerts != prefs.alerts || previous.holyDays != prefs.holyDays || previous.lead != prefs.lead || previous.sound != prefs.sound || previous.timezone != prefs.timezone || previous.address != prefs.address {
            let enabling = (!previous.alerts && prefs.alerts) || (!previous.holyDays && prefs.holyDays)
            enqueueReminders(requestPermission: enabling)
        }
    }
    func refresh() async {
        guard prefs.hasLocation else { isRefreshing = false; error = PrayerServiceError.noLocation.localizedDescription; return }
        generation += 1
        let token = generation
        let snapshot = prefs
        isRefreshing = true
        error = nil
        defer { if token == generation { isRefreshing = false } }
        do {
            let result = try await service.load(preferences: snapshot, now: now)
            try Task.checkCancellation()
            guard token == generation, prefs.calculation == snapshot.calculation else { return }
            schedule = result
            nextRetry = .distantPast
            if let data = try? JSONEncoder().encode(result) { defaults.set(data, forKey: "prayerSchedule") }
            await updateReminders()
        } catch is CancellationError {
            // A newer settings selection owns the refresh.
        } catch {
            guard token == generation else { return }
            nextRetry = now.addingTimeInterval(300)
            self.error = today == nil ? error.localizedDescription : "Could not refresh. Showing saved times. \(error.localizedDescription)"
        }
    }
    func tick(at date: Date = Date()) async {
        now = date
        if prefs.fastingDate != nil && !fastingToday { prefs.fastingDate = nil }
        if prefs.timezone == "System", observedSystemZone != TimeZone.current.identifier {
            observedSystemZone = TimeZone.current.identifier
            enqueueReminders()
        }
        let fetchedToday = currentSchedule.map { dateKey($0.fetchedAt) == dateKey(now) } ?? false
        if !loading && prefs.hasLocation && (!fetchedToday || nextRetry != .distantPast) && now >= nextRetry { await refresh() }
    }

    private func enqueueReminders(requestPermission: Bool = false) {
        pendingPermissionRequest = pendingPermissionRequest || requestPermission
        let previous = notificationTask
        previous?.cancel()
        notificationTask = Task { [weak self] in
            await previous?.value // An old add must finish before a newer replacement starts.
            guard let self, !Task.isCancelled else { return }
            await self.performReminderUpdate()
        }
    }
    func updateReminders(requestPermission: Bool = false) async {
        enqueueReminders(requestPermission: requestPermission)
        await notificationTask?.value
    }
    private func performReminderUpdate() async {
        do {
            var access = await notifications.access()
            guard !Task.isCancelled else { return }
            if pendingPermissionRequest && access == .notDetermined && (prefs.alerts || prefs.holyDays) {
                access = try await notifications.requestAccess() ? .authorized : .denied
            }
            guard !Task.isCancelled else { return }
            pendingPermissionRequest = false
            let plan = access == .authorized ? ReminderPlan.make(schedule: currentSchedule, preferences: prefs, now: now) : []
            try await notifications.replace(with: plan)
            guard !Task.isCancelled else { return }
            switch access {
            case .denied: notificationStatus = "Allow pray.daily in \(systemSettings) → Notifications to receive reminders."
            case .notDetermined: notificationStatus = "Enable a reminder to allow notifications on this device."
            case .authorized:
                if !prefs.alerts && !prefs.holyDays { notificationStatus = "Reminders are off." }
                else if today == nil { notificationStatus = "Reminders need current prayer times. Set a location or retry the refresh." }
                else { notificationStatus = "\(plan.count) reminders scheduled. Changes save automatically." }
            }
        } catch is CancellationError {} catch {
            notificationStatus = "Could not schedule reminders: \(error.localizedDescription)"
        }
    }
    func testNotification() async {
        do {
            var access = await notifications.access()
            if access == .notDetermined { access = try await notifications.requestAccess() ? .authorized : .denied }
            guard access == .authorized else {
                notice = "Allow pray.daily in \(systemSettings) → Notifications, then try again."
                return
            }
            await notificationTask?.value
            try await notifications.sendTest(sound: prefs.sound)
            notice = "Test notification scheduled for three seconds from now."
        } catch { notice = "Could not send test notification: \(error.localizedDescription)" }
    }

    func findAddress(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isLocating else { return }
        isLocating = true
        error = nil
        defer { isLocating = false }
        do {
            let places = try await geocoder.geocodeAddressString(query)
            guard let place = places.first, let point = place.location else { throw URLError(.cannotFindHost) }
            applyLocation(point, name: locationName(place, fallback: query))
        } catch { self.error = "Location could not be found. Try a city and country or a complete address." }
    }
    private func locationName(_ place: CLPlacemark, fallback: String) -> String {
        let name = [place.locality ?? place.name, place.administrativeArea, place.isoCountryCode].compactMap { $0 }.joined(separator: ", ")
        return name.isEmpty ? fallback : name
    }
    private func applyLocation(_ point: CLLocation, name: String) {
        var updated = prefs
        updated.latitude = point.coordinate.latitude
        updated.longitude = point.coordinate.longitude
        updated.address = name
        let sameCalculation = updated.calculation == prefs.calculation
        prefs = updated
        locationQuery = name
        if sameCalculation {
            refreshTask?.cancel()
            refreshTask = Task { await self.refresh() }
        }
    }
    func locate() {
        guard !isLocating else { return }
        error = nil
        guard CLLocationManager.locationServicesEnabled() else {
            error = "Enable Location Services in \(systemSettings) or enter a city."
            return
        }
        isLocating = true
        switch location.authorizationStatus {
        case .notDetermined:
            waitingForLocationAuthorization = true
            location.requestWhenInUseAuthorization()
        #if os(macOS)
        case .authorizedAlways: location.requestLocation()
        #else
        case .authorizedAlways, .authorizedWhenInUse: location.requestLocation()
        #endif
        default:
            isLocating = false
            error = "Location access is disabled. Allow pray.daily in \(systemSettings) or enter a city."
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard waitingForLocationAuthorization else { return }
            switch location.authorizationStatus {
            case .notDetermined: return
            #if os(macOS)
            case .authorizedAlways:
                waitingForLocationAuthorization = false
                location.requestLocation()
            #else
            case .authorizedAlways, .authorizedWhenInUse:
                waitingForLocationAuthorization = false
                location.requestLocation()
            #endif
            default:
                waitingForLocationAuthorization = false
                isLocating = false
                error = "Location access was not granted. Enter a city to continue."
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let point = locations.last(where: { $0.horizontalAccuracy >= 0 })
        Task { @MainActor in
            defer { isLocating = false }
            guard let point else { error = "Could not determine your location. Enter a city to continue."; return }
            let place = try? await geocoder.reverseGeocodeLocation(point).first
            applyLocation(point, name: place.map { locationName($0, fallback: "Current location") } ?? "Current location")
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isLocating = false
            self.error = "Device location is unavailable. Enable Location Services or enter a city."
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}

# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this is

pray.daily — a native prayer/fasting companion. One shared Swift core (`Sources/Hilal/`) powers two apps:
- **macOS menu bar app** (macOS 14+, Apple Silicon), built with SwiftPM. Swift target is `Hilal`; product/executable and bundle are `pray.daily`. Bundle ID stays `com.reza.hilal` so existing preferences carry over — don't rename it.
- **iPhone app** (iOS 17+) in `Assets/ios/`, an XcodeGen project that compiles the same `Sources/Hilal` files plus iOS-only views in `Assets/ios/PrayDaily/`. Bundle ID `com.reza.praydaily`.

## Commands

```sh
./build.sh           # swift build -c release, assemble + ad-hoc sign pray.daily.app
./test.sh            # timing tests + behavior tests (offline, mocked)
./test.sh --live     # additionally hits the real AlAdhan API and Apple's geocoder
```

Tests do **not** use XCTest or `swift test`. `test.sh` compiles standalone executables with `swiftc` from an explicit file list, then runs them:
- `Tests/HilalTests/TimingTests.swift` — compiled with only `Timing.swift`.
- `Tests/HilalTests/BehaviorTests.swift` — compiled with `Timing, Preferences, PrayerService, Reminders, NotificationService, Model` (not `Hilal.swift`, which holds the macOS UI and `@main`).

Assertions are `precondition`-based (`check(...)`), so the first failure crashes the run. Each case is a `try await test("name") { ... }` block; there is no per-test filter — to run one test, temporarily comment out others or add an arg check like the existing `--live` handling. **If you add a new source file the Store depends on, add it to the `swiftc` line in `test.sh`.**

iOS (see `Assets/ios/README.md` for archive/TestFlight steps):
```sh
xcodegen generate --spec Assets/ios/project.yml   # after editing project.yml (source of truth for the Xcode project)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Assets/ios/PrayDaily.xcodeproj -scheme pray.daily -destination 'generic/platform=iOS' build
```
Select Xcode per command via `DEVELOPER_DIR`; don't change the global `xcode-select`. The TestFlight-accepted toolchain (Xcode 27.1) is extracted at `.build/toolchains/xcode-27.1/Xcode.app`. Bump `CURRENT_PROJECT_VERSION` in `project.yml` before each new upload.

## Architecture

- `Timing.swift` — AlAdhan response model (`Day`, `Prayer`, `Method`). Times are parsed from ISO 8601 with offsets into absolute `Date`s; invalid times return nil rather than being invented. `prayers` = the five daily prayers.
- `Preferences.swift` — `Preferences` (Codable, persisted as JSON in UserDefaults key `preferences`) and `PrayerClock` calendar/date-key helpers. `prefs.calculation` (location + method + Asr school + Hijri adjustment) identifies which schedule is valid.
- `PrayerService.swift` — `PrayerLoading` protocol + `PrayerService` fetching 7 days. Hijri adjustment is applied client-side by taking the Hijri date of the adjacent Gregorian day (AlAdhan's HJCoSA calendar ignores `adjustment`); prayer timings are never shifted. Display timezone is never sent to the API. Responses missing any of the five prayers are rejected.
- `Reminders.swift` — `ReminderPlan.make(schedule:preferences:now:)`: pure function producing pre-prayer, Qadr (Maghrib before Ramadan 19/21/23) and Eid (Fajr) reminders.
- `NotificationService.swift` — `ReminderScheduling` protocol + `SystemReminders` (UNUserNotificationCenter, triggers built from UTC date components to avoid DST drift).
- `Model.swift` — `@MainActor Store`, the single ObservableObject both UIs bind to. Owns persistence (`preferences`, cached `prayerSchedule`), debounced refresh on settings change, a `generation` counter so stale responses can't overwrite newer selections, serialized notification updates, 5-minute retry after failures (keeping cached times), location/geocoding, and fasting-day expiry. Dependencies (`UserDefaults`, `PrayerLoading`, `ReminderScheduling`, `now`, debounce) are injected — this is how BehaviorTests run with fakes and isolated defaults domains. Platform differences are `#if os(iOS)/os(macOS)`; resources load from `Bundle.module` under SwiftPM (`#if SWIFT_PACKAGE`) and `Bundle.main` in Xcode.
- `Hilal.swift` — macOS-only: `@main` `MenuBarExtra` + dashboard `Window`, and the `Dashboard` view. Excluded from the iOS target.
- `Assets/ios/PrayDaily/` — iOS app entry, `MobileRoot` (Today/Fasting/Settings tabs), `MobileSettings`, asset catalog colors (Ink, Sage, Paper, Panel).
- `methods.json` — 23 bundled calculation presets; SwiftPM resource and iOS bundle resource. Jafari (method 0) is the default.

Behavioral invariants the tests guard (keep them true): changing calculation settings hides the old schedule and removes its reminders until new times arrive; notification-only settings (sound, lead time, toggles) reschedule without refetching; display timezone changes never move a prayer instant; failed refresh keeps cached schedule and reminders.

## Resources

- `Resources/Info.plist`, `Resources/AppIcon.icns` — macOS bundle; copied by `build.sh`.
- `Resources/Sounds/{Glass,Ping,Pop,Azan}.aiff` — original alert tones generated by `scripts/generate-sounds.py`; shared by both apps. Azan plays when a prayer begins; the others are pre-prayer reminder choices.
- `Assets/Brand/` — icon source art and its generation prompt.
- `pray.daily.app` is a build output that lives in the repo root; regenerate it with `./build.sh` rather than editing it.

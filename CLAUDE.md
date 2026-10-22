# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

pray.daily — a native prayer/fasting companion. One shared Swift core (`Sources/PrayDaily/`) powers two apps:
- **macOS menu bar app** (macOS 14+, Apple Silicon), SwiftPM. Swift target is `PrayDaily`; product/executable and bundle are `pray.daily`. Bundle ID is `com.reza.praydaily`.
- **iPhone app** (iOS 17+) in `Assets/ios/`, an XcodeGen project compiling the same `Sources/PrayDaily` files (except `MacApp.swift`) plus iOS-only views in `Assets/ios/PrayDaily/`. Bundle ID `com.reza.praydaily`, team `G56KC8CS7Z`.

`AGENTS.md` and `CLAUDE.md` are identical twins — edit both. `.cursor/rules/*.mdc` repeats the same rules.

## Commands

```sh
./build.sh           # swift build -c release, assemble + ad-hoc sign pray.daily.app
./test.sh            # timing tests + behavior tests (offline, mocked)
./test.sh --live     # additionally hits the real AlAdhan API and Apple's geocoder
```

Tests do **not** use XCTest or `swift test`. `test.sh` compiles two standalone executables with `swiftc` from an explicit file list, then runs them:
- `Tests/PrayDailyTests/TimingTests.swift` — with only `Timing.swift`.
- `Tests/PrayDailyTests/BehaviorTests.swift` — with `Timing, Preferences, PrayerService, Reminders, NotificationService, Model` (not `MacApp.swift`: macOS UI + `@main`).

Gotchas:
- **A new source file that `Store` depends on must be added to the matching `swiftc` line in `test.sh`.** Nothing else compiles the package for tests.
- `TimingTests.swift` is a `@main struct` whose `static func main()` invokes each test method by hand — a new timing test that isn't added to that list never runs.
- Assertions are `precondition`-based (`check(...)`), so the first failure aborts the whole run. Behavior cases are `try await test("name") { ... }` blocks; there is no per-test filter — comment out the others or add an arg check like the existing `--live` handling.
- Behavior tests must use the existing fakes (`FakeLoader`, `FakeReminders`), the isolated `UserDefaults` suite, and an injected `now`. Never touch real notifications, location, or `.standard` defaults. Network checks belong only in `liveChecks()` behind `--live`.

iOS (see `Assets/ios/README.md` for archive/TestFlight steps):
```sh
xcodegen generate --spec Assets/ios/project.yml   # after editing project.yml (source of truth for the Xcode project)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Assets/ios/PrayDaily.xcodeproj -scheme pray.daily -destination 'generic/platform=iOS' build
```
Select Xcode per command via `DEVELOPER_DIR`; don't change the global `xcode-select`. The TestFlight-accepted toolchain (Xcode 27.1) is extracted locally at `.build/toolchains/xcode-27.1/Xcode.app` — `.build/` is gitignored, so it won't exist on a fresh clone. Don't hand-edit `PrayDaily.xcodeproj`.

Versioning: `Assets/ios/project.yml` holds `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`; keep `Resources/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`) aligned with it. Rules live in `VERSIONING.md` — bump the build number for every upload and never reuse an accepted one.

## Architecture

- `Timing.swift` — AlAdhan response model (`Day`, `Prayer`, `Method`). Times parse from ISO 8601 with offsets into absolute `Date`s; invalid times return nil rather than being invented. `prayers` = the five daily prayers.
- `Preferences.swift` — `Preferences` (Codable, JSON in UserDefaults key `preferences`) and `PrayerClock` calendar/date-key helpers. `prefs.calculation` (location + method + Asr school + Hijri adjustment) identifies which schedule is valid.
- `PrayerService.swift` — `PrayerLoading` protocol + `PrayerService`. Builds a 7-day schedule; when the Hijri offset is non-zero it also fetches the offset day(s) and borrows only their Hijri date, keeping that day's original prayer instants (AlAdhan's HJCoSA calendar ignores `adjustment`). Display timezone is never sent to the API. Requests go out in batches of 4 concurrently; HTTP 429 becomes `rateLimited`. A response must include Imsak and Sunrise and strictly ascending prayer times, else it's rejected.
- `Reminders.swift` — `ReminderPlan.make(schedule:preferences:now:)`: pure function producing pre-prayer, Azan (at prayer time), Qadr (Maghrib on the nights before Ramadan 19/21/23) and Eid (Fajr) reminders. Keeps only the 63 soonest future reminders (UNUserNotificationCenter's limit is 64).
- `NotificationService.swift` — `ReminderScheduling` protocol + `SystemReminders`. Triggers are built from absolute UTC date components so they survive DST and travel. Sound names map to `<Name>.aiff`; "Silent" and "Default" are special-cased.
- `Model.swift` — `@MainActor Store`, the single ObservableObject both UIs bind to. Owns persistence (`preferences`, cached `prayerSchedule`), debounced refresh on settings change (350 ms), a `generation` counter so stale responses can't overwrite newer selections, serialized notification updates, 5-minute retry after failures (keeping cached times), location/geocoding, fasting-day expiry, and a 1-second `tick()` timer that drives the daily refresh. Dependencies (`UserDefaults`, `PrayerLoading`, `ReminderScheduling`, `now`, debounce) are injected — that's how BehaviorTests run with fakes and isolated defaults domains. Platform differences use `#if os(iOS)/os(macOS)`; `methods.json` loads from `Bundle.module` under `#if SWIFT_PACKAGE`, else `Bundle.main`.
- `MacApp.swift` — macOS-only: `@main` `MenuBarExtra` + dashboard `Window`, and the `Dashboard` view. Excluded from the iOS target.
- `Assets/ios/PrayDaily/` — iOS app entry, `MobileRoot` (Today/Fasting/Settings tabs), `MobileSettings`, asset catalog colors (Ink, Sage, Paper, Panel).
- `methods.json` — 23 bundled calculation presets (id 0 = Jafari, the default); SwiftPM resource and iOS bundle resource.

Behavioral invariants the tests guard (keep them true): changing calculation settings hides the old schedule and removes its reminders until new times arrive; notification-only settings (sound, lead time, toggles) reschedule without refetching; display timezone changes never move a prayer instant; a failed refresh keeps the cached schedule and reminders.

## Resources

- `Resources/Info.plist`, `Resources/AppIcon.icns` — macOS bundle; copied by `build.sh`.
- `Resources/Sounds/{Glass,Ping,Pop,Azan}.aiff` — original alert tones generated by `scripts/generate-sounds.py`; shared by both apps. Azan plays when a prayer begins; the others are pre-prayer reminder choices.
- `Assets/Brand/` — icon source art and its generation prompt.
- `pray.daily.app` is a committed build output in the repo root; regenerate it with `./build.sh` rather than editing it (rebuilds show up as binary diffs in git).

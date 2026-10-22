# pray.daily

A native prayer and fasting companion for iPhone and Mac. The iPhone app requires iOS 17 or later; see [iPhone build and TestFlight instructions](Assets/ios/README.md). The menu bar app requires macOS 14 or later and is built for Apple Silicon, ad-hoc signed for local use.

## Open

Open `pray.daily.app`. Click the moon in the menu bar, enter a city and country or street address, and choose **Find location**. Alternatively, choose **Use my location** and allow macOS Location Services. No location is assumed on first launch.

The ellipsis menu opens a dashboard window, refreshes times, or quits the app. The Swift target is `PrayDaily`; the executable and app bundle are named `pray.daily` (bundle ID `com.reza.praydaily`).

## Settings

Settings save automatically. A calculation change refreshes prayer times after a short delay; an older request cannot overwrite a newer selection. Sound, lead-time, and notification toggle changes reschedule reminders without another prayer-time request.

| Control | Behavior |
| --- | --- |
| Find location | Apple geocodes the entered address, saves the resolved location, and loads its schedule. |
| Use my location | Waits for macOS authorization, requests a position, and loads that location's schedule. |
| Method | Sends the selected provider method; Jafari method 0 is the default. All 23 bundled named presets are available. |
| Asr convention | Sends standard/Shafi or Hanafi to the provider. |
| Display timezone | Formats the same prayer instants in the system or selected IANA timezone. Prayer-day dates remain local to the chosen location. A date suffix appears when a displayed time crosses into another day. |
| Hijri adjustment | Shifts the provider's Hijri calendar by −2 to +2 days, including month/year boundaries, without moving prayer times. Ramadan and holy-day reminders use the adjusted date. |
| Pre-prayer reminders | Schedules future prayers using the selected 10–30 minute lead time; turning it off removes those reminders. |
| Sound | Applies Silent, the system default, Glass, Ping, or Pop to pre-prayer reminders. Preview plays the selected sound; Test notification exercises actual delivery. |
| Azan | Plays the Azan tone when a chosen prayer begins. Separate from the pre-prayer sound. |
| Holy day reminders | Schedules Qadr at Maghrib on the days preceding Ramadan 19, 21, and 23; Eid al-Fitr and Eid al-Adha at Fajr. |
| Track a fast today | Enables voluntary fasting for the current date at the selected location; it expires the next day. Ramadan tracking is automatic. |

## Calculation and recovery

Times come from [AlAdhan](https://aladhan.com/prayer-times-api) using coordinates, calculation method, Asr convention, and ISO 8601 timestamps. The provider determines the location's timezone. Display timezone changes do not alter the request or the prayer's instant. Iftar follows the selected method's Maghrib, which is later than sunset for Jafari. Imsak is shown separately from Fajr.

The provider's default HJCoSA calendar ignores its `adjustment` parameter; [the API specification](https://api.aladhan.com/v1/documentation/openapi/prayer-times/yaml) limits that parameter to the mathematical calendar. pray.daily instead obtains the Hijri date for the adjacent Gregorian day and retains the original prayer timings. This also preserves the provider's month lengths.

The app stores seven days locally and refreshes on launch and on a new day at the selected location. Failed refreshes retain cached times and reminders for the same calculation, show an error, and retry after five minutes. Changing the location, method, Asr convention, or Hijri adjustment hides the old schedule and removes its reminders until replacement times arrive. A request that lacks any of the five prayers is rejected.

Coordinates and calculation settings are sent to AlAdhan; address lookup uses Apple. No account or API key is required. Device location updates only on explicit request. The app does not continuously track movement, and no launch-at-login setting is included.

Notification permission is required. The settings panel reports denied permission, scheduling failures, or the number of scheduled reminders. Pending reminders can fire while the app is closed; reopen it at least weekly to replenish them. Notification triggers use absolute UTC dates, and updates are serialized to avoid stale reminders after rapid edits.

Calculated times and Hijri dates should be checked against the user's local religious authority. Moon sightings may differ. The bundled presets do not include custom calculation parameters.

## Build and test

```sh
./build.sh
./test.sh
./test.sh --live
```

The build script assembles and ad-hoc signs `pray.daily.app`, including method definitions and alert sounds. Apple distribution signing/notarization is not included. The test runner uses standalone Swift assertions, with isolated preference domains and mocked notification access. `--live` additionally checks the actual prayer API and Apple's city geocoder using public sample cities; it does not request the device's position or enable user notifications.

## Verification on September 26, 2026

- All 25 timing and behavior tests pass and cover persistence, automatic settings application, Hijri month rollover, permission denial, reminder races, offline recovery, stale-response rejection, fasting expiry, next-day Fajr, DST, and silent notification triggers.
- All 23 bundled calculation presets returned prayer data for a sample location. Live seven-day API checks verify method changes, Hanafi Asr, Hijri adjustment, and display timezone independence. Apple's city geocoder was checked with London, United Kingdom.
- The Mac release app includes the new icon and original alert tones, builds, passes strict signature verification, and launches as a process.
- The iPhone simulator build, signed archive, and distribution IPA export succeed. Onboarding was visually inspected. The development app was installed and launched on the paired iPhone, with its running process verified. TestFlight version 1.0.0 (1) is now Testing in the Personal testing group, and the sole account-owner tester is Invited. Installation through TestFlight and physical-device notification/location flows remain to be confirmed; see [release status](Assets/ios/README.md).
- Native UI inspection timed out. The rendered controls, device-location permission flow, and actual macOS notification presentation/sound remain unverified. Use **Settings → Test notification** to confirm delivery after granting permission.

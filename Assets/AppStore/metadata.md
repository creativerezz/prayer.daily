# App Store listing — pray.daily (iPhone)

App Store Connect app ID `6816553437`, bundle ID `com.reza.praydaily`. Field limits are App Store Connect's; counts below were checked.

| Field | Value | Limit |
| --- | --- | --- |
| Name | pray.daily: Prayer Times | 24 / 30 |
| Subtitle | Salah times, Azan & Iftar | 25 / 30 |
| Primary category | Lifestyle | — |
| Secondary category | Reference | — |
| Price | Free | — |
| Age rating | 4+ (answer "None" / "No" to every questionnaire item) | — |
| Copyright | 2026 Reza Jafar | — |
| Support URL | https://rezajafar.com | — |
| Marketing URL (optional) | https://rezajafar.com | — |
| Privacy policy URL | Host `privacy-policy.md` and paste its URL here (required) | — |

## Promotional text (152 / 170)

```
Accurate daily prayer times for wherever you are, gentle reminders before each prayer, and Suhoor and Iftar countdowns. No account, no ads, no tracking.
```

## Keywords (95 / 100)

Comma-separated, no spaces. Words already in the name and subtitle are indexed automatically, so they are not repeated.

```
salah,namaz,adhan,azan,muslim,islam,ramadan,iftar,suhoor,fasting,hijri,fajr,maghrib,jafari,shia
```

## Description

```
pray.daily is a quiet companion for your daily prayers. Open it and see the one thing that matters: your next prayer and how long until it begins.

TODAY
• The five daily prayers for your location, with the next one highlighted
• A live countdown to your next prayer
• Sunrise, and the Hijri date alongside today's date

FASTING
• Imsak / Suhoor, Fajr and Iftar times at a glance
• Track a fast and see a countdown to Iftar
• Upcoming holy days for the week ahead

REMINDERS
• Pre-prayer reminders 10 to 30 minutes before each prayer
• Optional Azan when each selected prayer begins
• Laylat al-Qadr reminders on the nights before 19, 21 and 23 Ramadan, and Eid reminders at Fajr
• Original reminder tones, or silent

YOUR CALCULATION
• 23 calculation methods, with Jafari selected by default
• Standard (Shafi) or Hanafi Asr
• Hijri date adjustment of up to two days to match local moon sighting
• Choose a display timezone without moving any prayer time

PRIVATE BY DESIGN
No account, no advertising, no analytics. Your preferences and schedule stay on your iPhone. Search a city or use your location only when you ask; your chosen coordinates are sent to AlAdhan over HTTPS to calculate prayer times.

Hijri dates are calculated and may differ from local moon sighting. Please confirm dates and times with your community.
```

## What's New (first release)

```
The first release of pray.daily: daily prayer times, a next-prayer countdown, Suhoor and Iftar times, prayer and holy-day reminders, and 23 calculation methods.
```

## App Privacy (nutrition label)

Matches `Assets/ios/PrayDaily/PrivacyInfo.xcprivacy`.

| Question | Answer |
| --- | --- |
| Do you or your third-party partners collect data from this app? | Yes |
| Data type | Location → Precise Location |
| Purpose | App Functionality |
| Linked to the user's identity? | No |
| Used for tracking? | No |

Everything else (contact info, identifiers, usage data, diagnostics, and so on): not collected. Result shown on the store: **Data Not Linked to You — Location**.

## App Review notes

```
No account or sign-in is required.

To see prayer times, either type a city (for example "London") in the Today tab and tap Find location, or tap Use my location and allow location access. Location permission is optional.

Reminders are local notifications scheduled on the device. Turn on any toggle in Settings → Notifications, then tap Test notification to see one immediately.

Prayer times come from the public AlAdhan API (aladhan.com) over HTTPS.
```

Contact for review: Reza Jafar, reza@313labs.org.

## Export compliance

`ITSAppUsesNonExemptEncryption` is `false` in `Info.plist` (only OS-provided HTTPS), so no export compliance documents are needed.

## Assets in this folder

| File | Use |
| --- | --- |
| `icon-1024.png` | 1024×1024 opaque App Store icon (copied from the asset catalog; Xcode also uploads it with the build) |
| `screenshots/iphone-6.9/*.png` | 1320×2868 iPhone screenshots. 6.9" is the only required iPhone size; App Store Connect scales them for smaller iPhones |
| `privacy-policy.md` | Privacy policy text to host at the privacy policy URL |

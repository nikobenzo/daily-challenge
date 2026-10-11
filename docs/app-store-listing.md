# App Store listing drafts (iPhone)

Drafts for App Store Connect. Nothing here has been entered, uploaded or submitted. The app is **free**,
available in **all countries and regions**, and the wording is generic ("75-day challenge"): the "75 Hard"
trademark is not used anywhere in the app or this listing.

Limits and requirements were checked on developer.apple.com on 11 October 2026:

- [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information): promotional text 170 characters, description 4,000, keywords 100 bytes (each keyword over two characters; do not repeat the app name or use other apps' names), review notes 4,000 bytes, support URL must lead to real contact information.
- [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information): name 2 to 30 characters, subtitle up to 30, privacy policy URL required for iOS apps, primary and optional secondary category, age rating required.
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications): see [Screenshots](#screenshots).
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/) and [age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions).

## Name, subtitle, category

| Field | Draft | Length |
| --- | --- | --- |
| App name | Daily Challenge | 15 / 30 |
| Subtitle | 75-day habit and water tracker | 30 / 30 |
| Primary category | Health & Fitness | |
| Secondary category (optional) | Productivity | |

Check in App Store Connect that "Daily Challenge" is free to claim; if not, add a suffix such as "Daily Challenge: 75 Days".

## Promotional text (166 / 170)

Log four litres of water, your workout, walk, diet and reading each day. Watch your streak grow toward 75 days, with Home Screen widgets that let you tick things off.

## Description (1431 / 4,000)

```text
Daily Challenge keeps a 75-day challenge simple. Every day you have five things to do. Log them in a few taps, and see your streak grow.

THE FIVE DAILY REQUIREMENTS
• Water: a drawn jug fills as you log pours towards 4 litres. Add 450 ml in one tap, or log any amount.
• Workout and walk: mark each one done, or undo it.
• Diet: mark the day as pending, clean or missed.
• Bible reading: tick it off when you have read.

YOUR STREAK
See your current streak out of 75, your best streak, and milestones along the way. Tracking carries on after day 75.

EXTRAS
Add up to ten personal to-dos of your own. They carry over, marked Late, until you finish them. Extras never count towards a complete day or your streak.

HISTORY
Open the monthly calendar to see every day at a glance, and tap Edit this day to fix a missed tick or a pour you forgot.

HOME SCREEN AND LOCK SCREEN WIDGETS
Log water, tick your requirements and check off extras without opening the app. A Lock Screen ring shows today's water.

WATER REMINDERS
Optional reminders at the times you choose, which stop once you reach your goal.

ON ALL YOUR DEVICES
Sign in with your email and your progress syncs between your iPhone and your Mac. Everything is saved on your device first, so nothing is lost when you are offline.

PRIVATE BY DESIGN
No ads, no tracking and no analytics. You can delete your account and all of your data inside the app.

Free, with no purchases.
```

## Keywords (92 / 100 bytes)

```text
habit,water,hydration,tracker,streak,75 day,workout,walk,diet,checklist,routine,widget,goals
```

"daily" and "challenge" are left out because the name already indexes them.

## URLs

| Field | Value |
| --- | --- |
| Support URL | `https://[OWNER].github.io/daily-challenge/support.html` (the owner fills in once published) |
| Privacy Policy URL | `https://[OWNER].github.io/daily-challenge/privacy.html` |
| Marketing URL (optional) | `https://[OWNER].github.io/daily-challenge/` |

The pages are in [`site/`](../site/README.md), with the owner steps to fill the placeholders and publish them.
The support page lists a contact email, as Apple requires.

## Pricing and availability

- Price: **Free** (price tier 0), no in-app purchases, no subscriptions.
- Availability: **all countries and regions** (leave every storefront selected).
- Release: manual release after approval is recommended for the first version.

## Age rating

Answer the age-rating questionnaire in App Store Connect (App Information) as follows. Apple's current questions
cover in-app controls, capabilities, mature themes, medical or wellness, sexuality or nudity, violence and
chance-based activities.

| Question group | Answer |
| --- | --- |
| Parental controls, age assurance | No |
| Unrestricted web access | No (the app opens no web content) |
| User-generated content, social media, messaging or chat | No (extras are private to-dos, never shared) |
| Advertising | No |
| Profanity or crude humour, horror or fear, alcohol, tobacco or drug references | None |
| Medical or treatment information | None |
| Health or wellness topics | **Yes** (self-logged water, workouts, diet) |
| Mature or suggestive themes, sexual content or nudity | None |
| Violence of every kind, guns or other weapons | None |
| Gambling, simulated gambling, contests, loot boxes | None / No |

Expected result: 4+. If "Health or wellness topics: Yes" raises the rating in the current form, accept the rating
App Store Connect calculates; do not answer No to lower it. Not Made for Kids.

## App Privacy questionnaire (draft)

Matches the [privacy policy](../site/privacy.html): the account and challenge are stored in Supabase, emails go
through Resend, nothing is used for tracking, advertising or analytics, and the iPhone app links no third-party
analytics SDK (its dependencies are `supabase-swift` and its support packages).

**Do you or your third-party partners collect data from this app?** Yes.

| Data type | Collected for | Linked to the user | Used for tracking |
| --- | --- | --- | --- |
| Contact Info › Email Address | App Functionality (sign-in, account emails) | Yes | No |
| Health & Fitness › Fitness (water amounts, workout, walk, diet and reading marks) | App Functionality | Yes | No |
| User Content › Other User Content (names of the user's extras) | App Functionality | Yes | No |
| Identifiers › User ID (account ID) | App Functionality | Yes | No |
| Identifiers › Device ID (random per-install ID attached to each synced entry, never an advertising ID) | App Functionality | Yes | No |

Not collected: location, contacts, photos or video, audio, browsing or search history, purchases, financial info,
sensitive info, usage data (no analytics), diagnostics (no crash or performance reporting), advertising data.
No data is shared with a third party for its own purposes: Supabase and Resend process data on our behalf. The
water reminders are local notifications and send nothing off the device.

Owner checks before answering: (1) whether to list the per-install device ID (listed here to be safe; it is
created by the app and not an advertising or hardware identifier); (2) the Health & Fitness choice, recorded here as "Fitness"
because the data is self-logged habit data, not HealthKit; the app's privacy manifest declares Fitness too, so change
both if the owner picks "Health"; (3) that no SDK has been added since this draft. The app and the widget extension
each declare a `PrivacyInfo.xcprivacy` privacy manifest (see [docs/ios-testflight.md](ios-testflight.md)); it
matches this table.

## App Review notes (draft, 4,000 bytes max)

```text
Daily Challenge is a personal tracker for a 75-day daily challenge: water (4 litres), workout, walk, diet,
reading, plus optional personal to-dos ("extras").

Sign in with the demo account (email and password in the fields below). The account already has a challenge in progress, so no setup is
needed.
  Email:    [DEMO ACCOUNT EMAIL]
  Password: [DEMO ACCOUNT PASSWORD]

New accounts are created in the app with an emailed code (no links). The demo account does not need one.

Features to try: Today (tap + 450 ml, tick a requirement), History (calendar, Edit this day), Account
(water reminders, appearance, Manage extras). Widgets: add "Daily Challenge" widgets from the Home Screen gallery;
they read the same data and need no extra sign-in.

Account deletion: Account > Delete account (permanently deletes the account and its data).
Notifications are optional local water reminders, requested only when the user turns them on.
No ads, tracking, purchases or third-party analytics. Backend: Supabase (account and challenge sync).
Contact: yakovetskyi@icloud.com
```

Create the demo account on the production server before submitting, seed a few days of entries, and keep it
out of real use. The owner supplies the credentials; never commit them.

## Screenshots

Apple's [specification](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications):
PNG or JPEG, no alpha channel, one to ten screenshots per device size, portrait or landscape. The page groups
sizes by display: the **6.9-inch class (iPhone 17 Pro Max, 16 Pro Max, Air and similar) accepts 1260 × 2736,
1290 × 2796 or 1320 × 2868** and is optional (App Store Connect scales it down); **Dynamic Island (medium,
1179 × 2556 or 1206 × 2622) is listed as required with at least one screenshot**, and the 6.5-inch group
(1284 × 2778 or 1242 × 2688) is required if no 6.9-inch screenshots are given. App Store Connect scales larger
sizes down when the UI is the same, so the 6.9-inch set below should satisfy it; confirm in App Store Connect
when uploading, and supply a 1206 × 2622 set if it asks.

Raw captures (no captions, frames or marketing layout) are in
[`docs/screenshots/app-store/raw/`](screenshots/app-store/raw/): iPhone 17 Pro Max simulator, iOS 26.4,
1320 × 2868, no alpha, status bar fixed at 9:41 with full signal and battery, synthetic fixture data. Light mode
is primary, with a `-dark` twin of each.

| File | Shows |
| --- | --- |
| `01-today-{light,dark}.png` | Today: five rings, jug, extras with two **Late** items, streak |
| `02-history-{light,dark}.png` | History: monthly calendar and a complete day with extras |
| `03-account-{light,dark}.png` | Account: sync state, water reminders, appearance, extras |
| `04-widgets-home-{light,dark}.png` | Home Screen: Water, Daily requirements and Extras widgets placed |
| `05-widgets-home-carry-over-{light,dark}.png` | Home Screen widgets with Late extras |

Reproduce with `bash iOS/scripts/capture-app-store-screenshots.sh` (app screens) and
`WIDGET_SIMULATOR_ID=<disposable iPhone 17 Pro Max> WIDGET_CAPTURE_MODE=phase5 WIDGET_LAYOUT=a WIDGET_PLACE=1 WIDGET_VARIANTS=partial,carry-over APPEARANCE=light bash iOS/scripts/capture-widgets.sh`
(then `dark`), which writes into `docs/screenshots/ios/widgets/` from where the headline captures were copied.
Caveats: the fixtures show "Local only" on Today and History because they run offline, and the fixture's challenge
day differs between the in-app screens (Day 12) and the widget fixtures (Day 1 and Day 3). The marketing
screenshots composed from these should crop or avoid that, or re-seed a consistent fixture.

## Build for review

Upload an App Store build with `bash scripts/ios-archive.sh --app-store`
([steps](ios-testflight.md#app-store-builds---app-store)); the default export is internal TestFlight only and
cannot be submitted.

## Open items

- **Account deletion** is in the iPhone app (Account > Delete account, landed in 184a0f1), matching the privacy policy and review notes. Re-check the wording against the released build.
- **Privacy manifest:** done. `iOS/DailyChallenge/PrivacyInfo.xcprivacy` and `iOS/DailyChallengeWidgets/PrivacyInfo.xcprivacy` exist and `scripts/ios-archive.sh --check` verifies them in the archive. Re-check them against the App Privacy answers before submitting.
- **Contact email, owner name, published URLs and demo account** are placeholders.
- The GitHub repository description still says "75 Hard"; the public repository text is not part of the app but is visible next to the Pages site. Change it in the repository settings.

# App Store listing drafts (iPhone)

Drafts for App Store Connect. Nothing here has been entered, uploaded or submitted. The app is **free**,
available in **all countries and regions**, and the wording is generic ("75-day challenge"): the "75 Hard"
trademark is not used anywhere in the app or this listing.

Limits and requirements were checked on developer.apple.com on 11 October 2026 (counts below re-measured on 12 October 2026 for the custom goals text):

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

## Promotional text (154 / 170)

Five daily goals for your 75-day challenge: use the standard set or make them your own. Log water, add repeating extras, and tick things off from widgets.

## Description (2,233 / 4,000)

```text
Daily Challenge keeps a 75-day challenge simple. Every day you have five things to do. Log them in a few taps, and see your streak grow.

YOUR DAILY FIVE
Start with the standard five, or make them your own.
• Water: a drawn jug fills as you log glasses towards your goal, 4 litres by default. Add a glass in one tap (450 ml unless you change it), or log any amount.
• Workout and walk: by default a 45-minute workout and a 45-minute walk. Mark each one done, or undo it.
• Diet: mark the day as pending, clean or missed.
• Reading: by default 10 Bible pages. Tick it off when you have read.

MAKE THEM YOURS
Rename the two activities and the reading goal, with an optional amount, unit and icon. Pick a preset such as yoga, Pilates, stretching or audiobook, or type your own. Rename your diet. Set your own water goal from 1 to 5 litres and the size of your glass. Choose them when you start, and change them later from today: earlier days keep the goals they had. There are always five, the 75 days stay the same, and every goal has to be met for a day to count.

YOUR STREAK
See your current streak out of 75, your best streak, and milestones along the way. Tracking carries on after day 75.

EXTRAS
Add up to ten personal extras of your own. A one-off extra carries over, marked Late, until you finish it. An extra can also repeat: every day, on weekdays, on days you choose, or every few days. A repeating extra is never late. Extras never count towards a complete day or your streak.

HISTORY
Open the monthly calendar to see every day at a glance, and tap Edit this day to fix a missed tick or a pour you forgot.

HOME SCREEN AND LOCK SCREEN WIDGETS
Log a glass of water, tick your goals under their own names and check off extras without opening the app. A Lock Screen ring shows today's water.

WATER REMINDERS
Optional reminders at the times you choose, which stop once you reach your goal.

ON ALL YOUR DEVICES
Sign in with your email and your progress syncs between your iPhone and your Mac. Everything is saved on your device first, so nothing is lost when you are offline.

PRIVATE BY DESIGN
No ads, no tracking and no analytics. You can delete your account and all of your data inside the app.

Free, with no purchases.
```

## What's New (draft for the next iPhone version, 630 / 4,000)

The first App Store version needs no What's New text. Use this for the update that adds your own goals and repeating extras; check the version number against the build when it is uploaded.

```text
Make the challenge yours.

• Choose your own daily five when you start, or change them later from today. Rename the two activities and the reading goal with an amount, unit and icon, rename your diet, and set your own water goal (1 to 5 litres) and glass size. The standard five are still one tap. Earlier days keep the goals they had.
• Extras can now repeat: every day, on weekdays, on days you choose, or every few days. A repeating extra is never late.
• The + button and the Water widget pour your own glass size, and the widgets show your goal names.
• The 75 days are unchanged, and a missed day still restarts your streak.
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
| Health & Fitness › Fitness (water amounts, workout, walk, diet and reading marks, and the water goal and glass size the user chose) | App Functionality | Yes | No |
| User Content › Other User Content (names of the user's extras and of their own goals, with the amounts, units and icons chosen) | App Functionality | Yes | No |
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

## App Review notes (1.1, 4,000 bytes max)

The paste-ready Notes text for **1.1 (11)** is in [app-review-1.1.md](app-review-1.1.md#2-app-review-information-notes)
(3,026 bytes with the `[DEMO EMAIL]` and `[DEMO PASSWORD]` placeholders), together with the reply to App Review,
the screen-recording shot list and the demo account steps. It replaces the build 1.0 (9) notes: it describes the
standard five as the default, Account › Daily goals (water goal 1,000 to 5,000 ml, glass size from presets or
Other…, renamed activities, diet and reading), repeating extras, and deletion through Account › Delete account.

Tick **Sign-in required** and enter the demo account there too. The demo account is a separate, dedicated
account, not the owner's, with a start date 8 to 10 days back, populated history, at least one personalised goal
and a repeating extra, and it is never deleted ([steps](app-review-1.1.md#4-demo-account)). Apply the account
deletion and custom goals server updates before creating it. The owner supplies the credentials; never commit them.

## Screenshots

Apple's [specification](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications):
PNG or JPEG, no alpha channel, one to ten screenshots per device size, portrait or landscape. The page groups
sizes by display: the **6.9-inch class (iPhone 17 Pro Max, 16 Pro Max, Air and similar) accepts 1260 × 2736,
1290 × 2796 or 1320 × 2868** and is optional (App Store Connect scales it down); **Dynamic Island (medium,
1179 × 2556 or 1206 × 2622) is listed as required with at least one screenshot**, and the 6.5-inch group
(1284 × 2778 or 1242 × 2688) is required if no 6.9-inch screenshots are given. App Store Connect scales larger
sizes down when the UI is the same, so the 6.9-inch set below should satisfy it; confirm in App Store Connect
when uploading, and supply a 1206 × 2622 set if it asks.

Upload the composed frames in [`docs/screenshots/app-store/marketing/`](screenshots/app-store/marketing/README.md):
seven 1320 × 2868 PNGs in `iphone-6.9/` and seven 1206 × 2622 PNGs in `iphone-medium/`, in file order, all opaque
RGB. For 1.1 they show the personalised goals (Gym, Yoga, No sugar, Audiobook, a 3,000 ml goal and a 330 ml
glass) on Today, the water close-up and History, and repeating extras beside a Late to-do on the extras close-up and
the Dark frame. The Home Screen widgets and the all-complete frame keep the standard five, which every new
challenge starts with.

Raw captures (no captions, frames or marketing layout) are in
[`docs/screenshots/app-store/raw/`](screenshots/app-store/raw/): iPhone 17 Pro Max simulator, iOS 26.4,
1320 × 2868, no alpha, status bar fixed at 9:41 with full signal and battery, synthetic fixture data. Light mode
is primary, with a `-dark` twin of each.

| File | Shows |
| --- | --- |
| `01-today-goals-{light,dark}.png` | Today with personalised goals: Gym, Yoga, No sugar, Audiobook, 2,250 / 3,000 ml, + 330 ml |
| `02-history-goals-{light,dark}.png` | History: calendar, today's card with the personalised goals and the goal changes in Activity |
| `07-today-recurring-{light,dark}.png` | Today: extras repeating every day, on weekdays and on Fridays, beside a **Late** to-do |
| `01-today-{light,dark}.png` | Today with the standard five: rings, jug, extras with two **Late** items, streak |
| `02-history-{light,dark}.png` | History: monthly calendar and a complete day with extras |
| `03-account-{light,dark}.png` | Account: sync state, water reminders, appearance, Daily goals, extras, version |
| `04-widgets-home-{light,dark}.png` | Home Screen: Water, Daily requirements and Extras widgets placed |
| `05-widgets-home-carry-over-{light,dark}.png` | Home Screen widgets with Late extras |
| `06-today-complete-{light,dark}.png` | All five complete (also native 1206 × 2622 in `iphone-medium/`) |

Reproduce with `bash iOS/scripts/capture-app-store-screenshots.sh` (app screens; `DEVICE` and `MEDIUM_DEVICE` name
the simulators), `.build/app-store-venv/bin/python scripts/render-app-store-marketing.py` (frames, then `--header`)
and
`WIDGET_SIMULATOR_ID=<disposable iPhone 17 Pro Max> WIDGET_CAPTURE_MODE=phase5 WIDGET_LAYOUT=a WIDGET_PLACE=1 WIDGET_VARIANTS=partial,carry-over APPEARANCE=light bash iOS/scripts/capture-widgets.sh`
(then `dark`), which writes into `docs/screenshots/ios/widgets/` from where the headline captures were copied.
Caveats: the fixtures show "Local only" on Today and History because they run offline, and the fixture's challenge
day differs between the in-app screens (Day 12) and the widget fixtures (Day 1 and Day 3). Each frame is an
independent example; the gallery makes no claim that they are one session.

## Build for review

The build for review is **1.1 (11)** ([review pack](app-review-1.1.md#owner-steps-before-replying)). Upload an App Store build with `bash scripts/ios-archive.sh --app-store`
([steps](ios-testflight.md#app-store-builds---app-store)); the default export is internal TestFlight only and
cannot be submitted.

## Open items

- **Custom goals need the server update.** The Description, What's New and review notes describe your own goals and repeating extras. Apply `20261012000100_custom_targets_action_kinds.sql` once before any build that writes them reaches the demo account or the public ([owner step](production-sync.md#custom-goals-update-owner-only-once)), and re-check the wording against that build.
- **Screenshots** were re-rendered for 1.1 (13 October): Today, the water close-up and History show personalised goals, and the extras close-up and the Dark frame show repeating extras. The Home Screen widget frame still shows the standard five; a placed-widget capture with personalised goals would need a new widget fixture.

- **Account deletion** is in the iPhone app (Account > Delete account, landed in 184a0f1), matching the privacy policy and review notes. Re-check the wording against the released build.
- **Privacy manifest:** done. `iOS/DailyChallenge/PrivacyInfo.xcprivacy` and `iOS/DailyChallengeWidgets/PrivacyInfo.xcprivacy` exist and `scripts/ios-archive.sh --check` verifies them in the archive. Re-check them against the App Privacy answers before submitting.
- **Contact email, owner name, published URLs and demo account** are placeholders.
- The GitHub repository description still says "75 Hard"; the public repository text is not part of the app but is visible next to the Pages site. Change it in the repository settings.

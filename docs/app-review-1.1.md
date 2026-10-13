# App Review pack for Daily Challenge iOS 1.1 (11)

Apple asked for more information about iOS 1.0 (9) (Guideline 2.1, new developer account). Since build 9 the
app gained personalised daily goals, a water goal and glass size of your own in millilitres, and repeating
extras. Build 9 cannot read data written by those features, so the answer goes out with **1.1 (11)** and a
separate demo account. Everything below was checked against the 1.1 code (`VERSION`: 1.1, build 11) and the
simulator; nothing here was entered in App Store Connect, uploaded or tried on a real account.

Placeholders: `[DEMO EMAIL]` and `[DEMO PASSWORD]`. Never commit the real values.

Contents: [owner steps before replying](#owner-steps-before-replying), [1. reply to App Review](#1-reply-to-app-review),
[2. Notes field](#2-app-review-information-notes), [3. recording shot list](#3-screen-recording-shot-list-one-take-physical-iphone),
[4. demo account](#4-demo-account), [5. evidence](#5-evidence).

## Owner steps before replying

1. **Server updates.** Both must be applied once on the hosted project before the demo account or the
   recording uses 1.1: `20261011000100_account_deletion.sql` ([steps](production-sync.md#account-deletion-owner-only-once-before-app-review))
   and then `20261012000100_custom_targets_action_kinds.sql` ([steps](production-sync.md#custom-goals-update-owner-only-once)).
   Without the second, personalised goals and repeats stay on the phone with the note "Saved on this iPhone.
   The server needs an update before goal and repeat changes can sync…", so a reviewer signing in to the demo
   account on their own device would see the standard five instead.
2. **Build number.** `VERSION` stays at 1.1 (11). App Store Connect needs a build number that is new for the
   app's version train; build 11 has never been uploaded for the iPhone app (iPhone builds 9 and possibly 10 went
   up as 1.0), and 11 is higher than both, so no change is needed. The Mac 1.1 (11) release is a separate,
   Sparkle-distributed app and does not use the iPhone app's App Store Connect record.
3. **Upload an App Store build** (an internal-only build can never be submitted), in a terminal with the
   credential from [docs/ios-testflight.md](ios-testflight.md#app-store-builds---app-store):
   ```bash
   export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 ASC_KEY_ID=<KEYID> ASC_ISSUER_ID=<issuer>
   # or: export ASC_APPLE_ID=<apple id> ASC_KEYCHAIN_ITEM=dc-asc
   bash scripts/ios-archive.sh --app-store
   ```
   When it has processed, install it from TestFlight (internal testers can use App Store builds) and check that
   Account › Version reads `1.1 (11)`.
4. **Version record.** A 1.1 build can only be attached to an App Store version numbered 1.1. The version under
   review is 1.0 and has never been released, so its version number can be edited once the submission is no
   longer in review: if it still shows as in review, choose **Remove from Review**; then on the iOS app version
   page change the version from 1.0 to 1.1, pick build 1.1 (11) under **Build**, paste the Notes text below,
   upload the new screenshots and submit. Reply in the Resolution Center with the text below and the recording.
   Check this in App Store Connect; if the version field is not editable, stop and ask before doing anything else.
5. **What's New** is not shown for an app's first App Store version, so it can stay empty even though the first
   version is 1.1.
6. **Screenshots.** Upload the seven frames from `docs/screenshots/app-store/marketing/iphone-6.9/`
   (1320 × 2868) and, if App Store Connect asks for the medium display, `iphone-medium/` (1206 × 2622), in
   file order ([details](screenshots/app-store/marketing/README.md)).

## 1. Reply to App Review

Paste into the Resolution Center reply and attach the recording.

```text
Hello, and thank you for the review. We have answered with a new build, Daily Challenge 1.1 (11), which replaces build 1.0 (9). It adds personal daily goals, your own water goal and glass size, and repeating extras. Answers to your six points:

1. Screen recording: attached, captured on a physical iPhone running the latest iOS with build 1.1 (11). In one take it shows launching the app, creating an account with a code sent by email, setting up a challenge, a typical day (logging water, ticking goals, an extra), personalising a goal and the water amount, a repeating extra, History with Edit this day, a Home Screen widget, the Account screen, signing out, signing in again, and Account > Delete account through to the confirmation. The app has no content that other users can see (extras are private to-dos), so there is nothing to report or block, and it has no paid content or features.

2. Purpose and audience: Daily Challenge is a personal tracker for a 75-day daily challenge. Each day has five goals: water, two activities, a diet and a reading. By default they are 4 litres of water, a 45-minute workout, a 45-minute walk, a clean diet and 10 pages of reading; each user can rename them and set their own amounts, water goal and glass size. The app shows a daily checklist of rings, a water jug that fills as you log, a streak out of 75 days, a calendar history where a past day can be corrected, optional personal to-dos ("extras") that can repeat on chosen days, and Home Screen and Lock Screen widgets. It is for adults who want a simple, private way to keep a daily habit challenge. It is free, with no purchases and no ads.

3. Access: please sign in with the demo account below. Its challenge is already in progress with history, personalised goals and extras, so no setup is needed and no code is asked for.
   Email: [DEMO EMAIL]
   Password: [DEMO PASSWORD]
   Today: tap the + button to add a glass of water, tap the rings to tick goals. Account > Daily goals changes the goals and the water amount from today. Today > Manage extras (or Account > Extras) adds an extra and sets how it repeats. History: choose a past day and tap the pencil ("Edit this day") to correct it. Widgets: touch and hold the Home Screen, tap +, search "Daily Challenge". Please do not delete the demo account; a new account can be created in the app to try Delete account.

4. External services: Supabase (account sign-in and storage of the user's challenge entries so they sync between devices); Resend (delivers the sign-up and password-reset code emails for Supabase); GitHub Pages (hosts the privacy policy and support pages). Otherwise only Apple frameworks: WidgetKit and App Intents for the widgets, local notifications for optional water reminders, and the Keychain for the sign-in token. No analytics, advertising, payment or AI services, and no other third-party SDKs.

5. Regions: the app works the same in every country and region, with the same features and content, in English. The only variation is that each challenge uses a time zone chosen at setup (the iPhone's by default), and its days run from midnight to midnight in that zone.

6. Regulated industry and third-party material: the app is not in a regulated industry and contains no protected third-party material. It is a self-logging tool: it gives no medical advice, reads no HealthKit data, and uses generic wording ("75-day challenge") with no third-party program's name or trademark.

Support: yakovetskyi@icloud.com. The same information is in the App Review Information notes.
```

## 2. App Review Information Notes

Paste into App Store Connect › the 1.1 version › App Review Information › Notes. Also tick **Sign-in required**
and enter the same email and password in its username and password fields. Measured with the placeholders:
**3,026 bytes** (UTF-8, measured with `len(text.encode())`; limit 4,000). A real email and password add well under 100 bytes.

```text
Daily Challenge is a personal tracker for a 75-day daily challenge. Each day has five goals: water, two activities, a diet and a reading. By default: 4 litres of water, a 45-minute workout, a 45-minute walk, a clean diet and 10 pages of reading. Users can rename them and set their own amounts, water goal and glass size. Optional personal to-dos ("extras") can repeat on chosen days. Free, no purchases, no ads, no content shared with other users, all countries and regions, iPhone only.

DEMO ACCOUNT (challenge in progress, no setup and no code needed)
  Email:    [DEMO EMAIL]
  Password: [DEMO PASSWORD]
Please do not delete this account. To try Delete account, create a new account in the app.

MAIN FEATURES
- Today: tap + to add a glass of water (the jug fills toward the day's goal; - removes the latest pour; ... logs any amount in ml). Tap a ring to tick a goal; the diet ring cycles pending, clean and missed. Extras: tick a to-do; the pencil button (Manage extras) adds, renames, archives (up to 10) and sets how an extra repeats. A one-off extra carries over, marked Late; a repeating one shows on its days.
- Account > Daily goals: change the water goal (1,000 to 5,000 ml), the glass size (presets or Other..., 50 to 1,000 ml), and the name, amount and icon of the activities, diet and reading. Changes apply from today; earlier days keep their goals.
- History: monthly calendar. Choose a past day and tap the pencil (Edit this day) to correct it.
- Account: water reminders (optional local notifications, permission asked only when turned on), appearance, Daily goals, Extras, Sign out on this iPhone, Delete account, Version.
- Widgets: touch and hold the Home Screen, tap +, search "Daily Challenge": Water (small, medium, Lock Screen), Daily requirements (medium), Extras (medium, large). Their buttons log water and tick goals without opening the app.

NEW ACCOUNT (optional)
Sign in screen > Create account: email and a password of 10+ characters with a letter and a number, then the 8-digit code emailed to that address (no links). Setup shows the five goals (one tap keeps the standard five), a start date and a time zone, then Start challenge.

ACCOUNT DELETION
Account > Delete account > "Delete account..." > "Delete account" in the alert. This permanently deletes the account, its email address and all its challenge data from the server, and the copy on the iPhone. It needs a network connection; the app then returns to Sign in.

EXTERNAL SERVICES
Supabase (sign-in, storage and sync of the user's entries); Resend (sign-up and password-reset code emails); GitHub Pages (privacy policy and support pages). Apple: WidgetKit, App Intents, local notifications, Keychain. No analytics, ads, payments or AI services; no other third-party SDKs.

REGIONS: identical everywhere, English only. Days run midnight to midnight in the challenge's time zone.
REGULATION: not a regulated industry; no medical advice; no HealthKit; no third-party trademarks.

Contact: Mykola Yakovetskyi, yakovetskyi@icloud.com
```

## 3. Screen-recording shot list (one take, physical iPhone)

About 3 to 4 minutes. Use build 1.1 (11) from TestFlight on a physical iPhone running the latest iOS, and a
**throwaway account** that you are happy to delete, because the take ends with deletion. Labels below are as
they appear on screen in 1.1 (ring names show in capitals).

**Before recording (not in the video)**

1. Update iOS. Install 1.1 (11); later in the take the Account › Version row must read `1.1 (11)`.
2. Have a throwaway email ready and its inbox open in Mail, so the code can be read quickly.
3. If the app is installed, sign out or delete and reinstall it so it opens on **Sign in**. Swipe it away so the
   take starts with a cold launch.
4. Free a Home Screen page for a widget. Turn on Do Not Disturb. Check Screen Recording is in Control Center and
   the microphone is off (long-press the record button).

**Start:** open Control Center, tap Screen Recording, wait for the countdown, close Control Center and tap the
**Daily Challenge** icon. Stop at the end with the red status-bar pill › Stop.

1. **Launch.** The app opens on **Sign in**. Pause a second.
2. **Create account.** Tap **Create account**. Type the throwaway email, then **Choose a password** (10+ characters
   with a letter and a number; the 10+, Aa, 0-9 and Match chips turn green) and **Repeat password**. Tap
   **Create account**.
3. **Emailed code.** The screen reads **Enter the code**. Switch to Mail, read the 8-digit code, switch back, type it
   into **Code from the email** (or tap the suggestion above the keyboard) and tap **Confirm email**. If it is slow,
   **Resend** is available after 60 seconds.
4. **Setup.** **Your next 75 days** shows **Your daily five** (Water 4,000 ml · 450 ml glass, Workout, Walk, Diet,
   Bible). Leave them as they are. Set **Start** to **three days ago** (so History has past days), tap **Time zone**
   if you want to show it, then tap **Start challenge**.
5. **A typical day.** On Today tap the **+ 450 ml** button twice (the jug fills), tap **−** once (removes the latest
   pour), then **+ 450 ml** again. Tap **WORKOUT** and **WALK** to tick them, tap **DIET** once (clean).
6. **Personalise a goal.** Tap the **Account** tab › **Daily goals**. Tap **Walk**; on **Second activity** choose
   **Yoga** (30 min) and tap **Done**.
7. **Personalise the water amount.** Still in **Daily goals**, tap **Water**. Under **Daily goal** tap **−** four
   times to **3,000 ml**. Under **Your glass or bottle** tap **Other…** and type **400** in **Glass size in ml**
   ("The + button adds 400 ml"). Tap **Done**, then **Done** to close Daily goals.
8. **Back on Today.** Tap the **Today** tab: the rings read WATER, WORKOUT, **YOGA**, DIET, BIBLE, the jug shows
   **/ 3,000** and the button reads **+ 400 ml**. Tap **+ 400 ml** once. Tap **⋯** (Custom pour), type **250**, tap
   **Add**.
9. **A repeating extra.** Tap **Extras · Add your own to-dos**. In **Manage extras** type **Stretch** in **New extra**,
   tap **Add extra**. On the Stretch row tap **Once ›**; on **Repeat** tap **Every day**, then **Done**. Add a second
   extra, **Book dentist** (leave it as Once). Tap **Done**. On Today, Stretch shows "every day"; tick it.
10. **History and Edit this day.** Tap **History**. Tap the day from two days ago: its controls are dimmed until
    you unlock it. Tap the **pencil** (Edit this day), tap **+ 450 ml** and one
    habit pill to correct the day, and scroll to **Activity** to show the corrections. Tap today's date to show
    today's card with YOGA and 3,000 ml.
11. **Widget.** Swipe home. Touch and hold an empty spot, tap **+** (top left), search **Daily Challenge**, choose
    **Water** (medium), **Add Widget**, then **Done**. Tap the widget's **+ 400 ml**; the total rises without opening
    the app. Optionally add **Daily requirements** too (it shows YOGA). Tap the app icon to return; Today shows the
    new total.
12. **Account.** Tap **Account**: the email, "Day 4 of 75", the sync line, **Water reminders** (turn on, allow the
    notification prompt, turn off), **Appearance** (tap **Dark**, then **System**), **Daily goals**, **Extras**, and
    **Version** `1.1 (11)`.
13. **Sign out.** Tap **Sign out on this iPhone** › **Sign out**. The app returns to **Sign in**.
14. **Sign in.** Type the same email and password, tap **Sign in**. Today returns with YOGA, 3,000 ml and the extras.
15. **Delete account.** Tap **Account** › **Delete account**. On **Delete your account?** pause a second, tap
    **Delete account…**, then **Delete account** in the **Delete your account permanently?** alert. The app returns
    to **Sign in** with "Your account and all its challenge history have been deleted." Hold two seconds.
16. **Stop recording.**

If anything goes wrong mid-take, stop, delete that account (Account › Delete account) and start again with a new
throwaway email. Do not cut the middle of the video; trimming the start and end is fine.

## 4. Demo account

A **separate, dedicated** account for Apple: not the owner's personal account (reviewers may test deletion on
whatever they are given), and not the throwaway used in the recording.

1. Apply both server updates in [owner steps](#owner-steps-before-replying) first.
2. On 1.1 (11), **Create account** with an address you control long term (an alias is fine) and a password that is
   easy to type: 10+ characters with a letter and a number. Confirm with the emailed code.
3. At setup, before **Start challenge**: set **Start** to **8 to 10 days ago**, and personalise at least one goal
   so every day shows it, for example **Walk › Yoga, 30 min** and **Water › 3,000 ml, 330 ml glass**. Goals chosen
   in setup apply from the start date. Keep the time zone you live in.
4. Populate the history: on most past days use **History › day › pencil** to add water (+ the glass) and tick
   goals. Make several days fully complete in a row so there is a streak, one or two partly done, and leave one
   empty so it shows missed.
5. Extras: add **Stretch** and set it to **Every day** (repeating), add **Book dentist** and leave it as **Once**
   (it carries over, marked Late, until ticked). Optionally a weekdays one such as **Pack lunch**.
6. Leave today partly done so the reviewer can tick more. Check that Account › Daily goals shows no amber "Saved on
   this iPhone…" note (that note means the custom goals server update is missing).
7. Sign out on the phone you used. Then, just before submitting, sign in from a fresh install: no setup and no
   code are asked for, and the goals, history and extras appear.
8. **Never delete it** during review, after approval or before future submissions; keep it out of real use.
   Enter the credentials only in App Store Connect (Sign-in required fields, the Notes text and the reply), never
   in this repository.

## 5. Evidence

Checked on branch `fm/dc-iphone-110` at `1183ebe` plus this commit (build number unchanged).

- **Version:** `VERSION` 1.1 / 11. The archived app and widget extension both read `CFBundleShortVersionString`
  1.1 and `CFBundleVersion` 11.
- **Archive check** (`bash scripts/ios-archive.sh --check`, no credentials, nothing uploaded): passed. The app and
  `DailyChallengeWidgets.appex` are signed with App Group `group.app.daily-challenge.ios`
  (`codesign -d --entitlements` shows it on both); privacy manifests present in both (no tracking, UserDefaults
  CA92.1, five collected data types in the app only); UIDeviceFamily 1; embedded WidgetKit extension, matching
  versions and extension-only widget intents verified.
- **Tests:** `swift test`: 245 tests passed, none failed. `xcodebuild test` (iPhone 17, iOS 27.0, dedicated
  simulator): 57 unit tests and 22 UI tests passed, including the custom goals UI tests (setup editors, Daily goals
  changing the glass from today, editor limits, repeat picker, custom goals on Today and History, unmigrated
  server note); the 7 widget-placement UI tests skip by design outside the WidgetCapture scheme.
- **Simulator run:** the Debug 1.1 (11) app on iOS 27.0 opened Daily goals › Water (3,000 ml, 330 ml glass,
  presets 250, 330, 450, 500, 750 ml and Other…), Second activity (Yoga, 30 min) and Repeat (Once, Every day,
  Weekdays, Choose days, Every N days) on fixtures; no account, Keychain or network.
- **Labels** quoted in the shot list come from `AuthScreen.swift`, `SetupScreen.swift`, `GoalEditors.swift`,
  `TodayScreen.swift`, `PhoneExtrasViews.swift`, `HistoryScreen.swift`, `AccountScreen.swift`, the widget
  configuration names in `ChallengeWidgets.swift` and the deletion notice in `AuthModel.swift`.
- **Services:** imports across the iPhone app, widgets and shared code are Foundation, SwiftUI, UIKit, WidgetKit,
  AppIntents, UserNotifications, BackgroundTasks, Network, Observation and Supabase; no StoreKit, HealthKit,
  CoreLocation, analytics, advertising or AI code; no web links in the app. `Package.resolved`, `iOS/project.yml`,
  the entitlements and both privacy manifests are unchanged since build 9.
- **Not verified here:** App Store Connect state and whether its version field is editable, the hosted
  migrations, the live privacy and support pages, and anything on a real iPhone or real account.

### Open points

- The support page and the site index have a "Buy me a coffee" footer link. It is outside the app (the app has no
  link to it), but a reviewer opening the support URL will see it.
- The header creative (`marketing/header/`) now uses the personalised Today capture beside the standard-goal
  widgets; both are real captures.

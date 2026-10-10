# iPhone app: build, TestFlight and owner steps

The iPhone app (`iOS/`) shares the challenge rules (`ChallengeCore`) and the auth, sync and
reminder code (`ChallengeSyncKit`) with the Mac app, so both clients read and write the same
events. Family members get it through **TestFlight internal testing**, not the App Store.

- Bundle identifier `app.daily-challenge.ios`, team `L644Y3WX5T`, automatic signing.
- Deployment target iOS 26. Sparkle is not linked (the Mac target alone depends on it).
- Its own Keychain items (`app.daily-challenge.ios.auth`, no shared access group), coordinated history in App Group
  `group.app.daily-challenge.ios`, and device-local reminder and appearance settings. The same account works on the
  Mac; an iPhone signing in to an account whose Mac already has a challenge adopts it after a
  successful server check, exactly as a second Mac does.

## Build and run (developers)

```bash
cp .env.example .env.local          # public SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY only
open iOS/DailyChallenge.xcodeproj   # or:
xcodebuild -project iOS/DailyChallenge.xcodeproj -scheme DailyChallenge \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild test -project iOS/DailyChallenge.xcodeproj -scheme DailyChallenge \
  -destination 'platform=iOS Simulator,name=iPhone 17'
bash iOS/scripts/capture-screenshots.sh   # every screen, Light and Dark, into docs/screenshots/ios/
```

The **Bundle configuration and version** build phase (`iOS/scripts/bundle-configuration.sh`)
writes `Configuration.json` from `.env.local` (the same public URL and publishable key as the
Mac build) and the version from `VERSION` into the built app. Nothing is hard-coded or
committed. A Debug build without `.env.local` shows "Configuration unavailable"; a Release
build refuses.

The Xcode project is generated from `iOS/project.yml` with XcodeGen and committed, so building
never needs XcodeGen. After editing `project.yml`, or adding or removing a source file in
`iOS/` or `Sources/DailyChallengeProof/Shared/`, run `cd iOS && xcodegen generate` and commit
both.

Debug builds accept `-fixture <screen>` (and `-appearance light|dark`) as launch arguments to
open on offline fixture data for UI tests and screenshots; Release builds do not contain the
fixtures.

## Extras and widgets

The [phased iPhone widgets plan](../plans/ios-widgets.md) defines extras UI, coordinated App
Group storage, three widgets and owner signing/TestFlight acceptance. Phase 1 phone extras,
Phase 2 coordinated storage and Phase 3 read-only widgets are built; Phases 4–5 remain planned. Each phase has its own review gate.

Phase 1 fixture acceptance (10 October 2026) uses Xcode 27.0 (27A266a), iPhone 17 / iOS 27.0.
Commands A–D in the plan passed: XcodeGen regeneration, `swift test` (183 shared tests),
`xcodebuild test` (9 phone unit tests and 12 UI tests), and the screenshot helper. Tests cover
empty entry points, add/rename/archive and cancellation, the 10-active cap, title validation,
historical locking and relocking, archived extras on older days, and unchanged completion/streaks.
The hosted test app also launches on temporary fixture auth/storage.

All evidence below is from the running simulator app on synthetic fixtures, captured in Light
and Dark under [screenshots/ios/](screenshots/ios/); these are not in-process renders or real-phone
sync acceptance. Add `-light.png` / `-dark.png` to each prefix:

| Surface | Screenshot prefixes |
| --- | --- |
| Empty / populated Today | `today`, `todayExtras`, `today-extras-detail`, `extrasCap` |
| Manage extras: empty / populated / cap | `manage-extras-empty`, `manage-extras`, `manage-extras-cap` |
| Account entry point: empty / populated | `account`, `accountExtras` |
| History: locked / unlocked | `historyExtras`, `historyExtrasEditing` |
| Accessibility Large text | `today-extras-large-text`, `manage-extras-large-text`, `manage-extras-actions-large-text`, `history-extras-large-text`, `account-extras-large-text` |

The accessibility captures and interactive UI test verify wrapping checklist titles, growing
management controls and scrolling to lower rows; text is not clipped inside the extras controls.
Debug fixture launches reset restored scroll positions and can select a capture anchor, so the
helper is reproducible. Owner real-device/sync acceptance remains the checklist below.


Phase 2 uses fresh-load synchronous transactions under a stable advisory lock; no lock spans
network awaits. Active metadata contains only owner UUID, generation and challenge ID.
Session changes invalidate visibility immediately, while dormant history stays available for
later sign-in. There are no credentials in the group. Foreground and background refresh reload
committed disk state. Shared files use protection after first unlock; simulator tests inject
unavailability, while actual pre-first-unlock protection remains signed-device acceptance.

First launch stages and validates a copy of private phone history, pending queues, device IDs,
recovery backups and celebration ledgers. Originals remain untouched; appearance/reminders
stay device-local. Interrupted copies retry; differing destination history shows **History
unavailable** with a storage-recovery explanation, never empty setup. Keep both copies for
recovery; do not delete or manually overwrite them. `-fixture sharedToday` and
`-fixture storageRecovery` exercise these paths with temporary synthetic roots only. See
[Phase 2 verification evidence](ios-widgets-phase2-evidence.md).

## What the iPhone app does in v1

Sign in, create an account and reset a password with the emailed code; setup (start date and
timezone) only after the server confirms there is no challenge yet; Today (five rings, jug,
streak, day number); History (calendar, Edit this day for late entries, activity); Account
(email, sync status and Sync now, water reminders, appearance, sign out on this iPhone).
Completing, undoing, late entries and conflicts follow the same rules as the Mac.

- **Sync** runs at launch, when the app comes to the foreground, every 30 seconds while it is
  open, on reconnect, after each edit, and in a background app refresh (`BGAppRefreshTask`,
  `app.daily-challenge.ios.refresh`) at times iOS chooses. Entries made offline wait in the
  same durable queue as on the Mac. Nothing else runs in the background.
- **Water reminders** are off until turned on in Account, and notification permission is asked
  only then. Unlike the Mac (one request a minute ahead while the app runs), the iPhone queues
  every remaining slot of today and tomorrow (`ReminderPolicy.queued`), because a suspended
  app cannot schedule the next one in time. They are re-planned whenever the app learns a new
  total: an edit, a foreground sync or a background refresh. A goal met on the Mac therefore
  stops the iPhone's reminders only after the iPhone has synced; a reminder can still arrive in
  between.
- **Extras:** optional daily to-dos on Today, including an empty Add your own to-dos entry.
  Today and Account open the same Manage extras sheet: add, rename and permanently archive
  with confirmation, up to 10 active, one-line titles of 1–40 characters. History uses that
  day’s extras (including ones archived later) and requires Edit this day for ticks. Extras
  never affect complete days or streaks. Activity explicitly labels names, archives and ticks.
- **Not in v1:** backups,
  change password, account deletion, widgets.

## One-time owner steps

These need the Apple Developer Program membership (team `L644Y3WX5T`). TestFlight 0.3.0 (3)
already exists; preserve installed history. This phase's worker did not inspect or change team
registration, provisioning, credentials or uploads. The App Group association is a new owner
step; the remaining items below describe the existing distribution workflow.

1. **Xcode account.** Xcode › Settings › Accounts › + › Apple Account: sign in with an account
   that is Admin or Account Holder in the team. (Needed for the app-specific-password route;
   the API-key route signs without it.)
2. **App ID.** Either let the first archive create it (automatic signing with
   `-allowProvisioningUpdates` registers `app.daily-challenge.ios`), or create it yourself:
   developer.apple.com › Certificates, Identifiers & Profiles › Identifiers › + › App IDs ›
   App, explicit Bundle ID `app.daily-challenge.ios`, description "Daily Challenge iPhone". No
   background-refresh or local-notification capabilities are needed. Enable **App Groups**,
   register `group.app.daily-challenge.ios` on team `L644Y3WX5T`, and attach it to this App ID
   before signed-device acceptance. See [Apple’s configuration guide](https://developer.apple.com/documentation/xcode/configuring-app-groups)
   and [manual registration fallback](https://developer.apple.com/help/account/identifiers/register-an-app-group).
   Automatic signing can manage provisioning; an unsigned archive or an upload alone does
   not prove the group is registered and authorized. Phase 3 will add the extension association.
3. **App Store Connect record.** appstoreconnect.apple.com › Apps › + › New App: platform iOS,
   name "Daily Challenge" (App Store names are unique across Apple; if it is taken, choose
   another, such as "Daily Challenge 75": testers see it in TestFlight), primary language
   English (U.K.), bundle ID `app.daily-challenge.ios`, SKU `daily-challenge-ios`, User Access
   Full Access.
4. **Upload credential**, one of:
   - **API key (recommended).** Users and Access › Integrations › App Store Connect API › Team
     Keys › +: name "Daily Challenge uploads", access **Admin** (Apple issues the cloud-managed
     distribution certificate only to Admin keys; an App Manager key fails the export with
     "Cloud signing permission error"). Download
     `AuthKey_<KEYID>.p8` (it can be downloaded only once) to
     `~/.appstoreconnect/private_keys/` and `chmod 600` it. Never put it in this repository or
     in `.env.local`. Note the Key ID and the Issuer ID shown above the list.
   - **App-specific password.** account.apple.com › Sign-In and Security › App-Specific
     Passwords › +, then store it once in the login keychain:
     `xcrun altool --store-password-in-keychain-item dc-asc -u <apple id> -p <app-specific password>`.
5. **Internal tester group.** App Store Connect › the app › TestFlight › Internal Testing › +:
   group "Family", with **Automatic Distribution** on. Internal testers must be users of the
   App Store Connect team (Users and Access › + with any role, for example Customer Support);
   up to 100. Add them to the group; they get an email invitation and install the free
   TestFlight app on their iPhone.
6. **Export compliance** is answered in the build (`ITSAppUsesNonExemptEncryption = NO`: the app
   uses only the system's HTTPS). Confirm this is still true before each release.

## Per-build steps

1. Raise `CFBundleVersion` in `VERSION` (every upload needs a new build number; the Mac and
   iPhone builds share the file) and `CFBundleShortVersionString` when the version changes.
2. Optional check, no credentials and no upload: `bash scripts/ios-archive.sh --check`
   (unsigned Release archive; confirms the configuration is bundled and Sparkle is absent).
3. In a terminal with the credential from step 4 above:
   ```bash
   export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 ASC_KEY_ID=<KEYID> ASC_ISSUER_ID=<issuer>
   # or: export ASC_APPLE_ID=<apple id> ASC_KEYCHAIN_ITEM=dc-asc
   bash scripts/ios-archive.sh
   ```
   It archives with automatic signing, exports with an `app-store-connect` export options plist
   (`testFlightInternalTestingOnly`, build number managed by `VERSION`) and uploads, through
   `xcodebuild -exportArchive`'s upload destination with the API key or `xcrun altool
   --upload-app` with the keychain item. It refuses to run without one of the two credentials
   and prints these steps.
4. Wait for App Store Connect's "ready to test" email (usually minutes). With Automatic
   Distribution the "Family" group gets the build; otherwise TestFlight › the build › Groups ›
   add "Family". Add a short "What to Test" note.

## What TestFlight internal testing does and does not review

- **Internal builds are not reviewed by App Review.** They are available to the internal group
  as soon as processing finishes. Apple still runs automated upload checks (signing, icon
  without transparency, Info.plist keys, private API use).
- Builds **expire after 90 days**; testers need a newer build after that.
- Internal testers must be App Store Connect users of the team (up to 100). There is no public
  link. Builds uploaded by this script are marked internal-only and cannot be moved to
  external testing.
- **External testing** (up to 10,000 people, invitation or public link) requires Beta App Review
  of the first build of each version, test information and a privacy policy, and is judged
  against the App Review Guidelines, which include in-app account deletion for apps that
  create accounts (guideline 5.1.1(v)). The app does not offer account deletion yet, so stay
  with internal testing until it does.
- App Store release is out of scope.

## Owner acceptance checklist (on a real iPhone)

The worker verified the app only in the iPhone 17 simulator on fixtures and with fake
transports. On a real iPhone, after installing from TestFlight:

1. Sign in with the existing account; the challenge, start date, timezone and history match the
   Mac without a setup screen.
2. Add 450 ml on the iPhone; within a minute the Mac shows it (open the popup). Add one on the
   Mac; bring the iPhone app to the foreground and it appears.
3. Airplane mode: add water and tick a habit, quit the app, reopen, turn the network back on;
   both entries sync and the Mac shows them.
4. History › a past day › Edit this day › add a late entry; streaks recalculate on both devices.
5. Account › Water reminders on: allow notifications when asked; leave the app; a reminder
   arrives at the next slot. Meet 4,000 ml and no more reminders arrive that day.
6. VoiceOver reads the rings ("Water, 2,250 of 4,000 millilitres") and the jug; Larger Text,
   Reduce Motion and Reduce Transparency behave as in Settings › Accessibility.
7. Sign out on this iPhone; the Mac stays signed in.

8. Before real extras sync acceptance, confirm the existing [extras action-kind migration](production-sync.md#extras-update-owner-only-once)
   is deployed; no new migration accompanies the phone UI. From Today’s empty Extras row and
   Account → Extras, open Manage extras; add, rename, cancel an archive, then confirm an archive.
   At 10 active extras the inline cap explains how to add another. Blank, multiline and >40-character
   titles cannot save. Ticks and management leave complete days and streaks unchanged.
9. History shows extras archived after the selected day. Its ticks remain disabled until
   Edit this day; choosing a different day exits correction mode. Check explicit extras activity
   wording, Light/Dark, VoiceOver and accessibility text sizes on the real phone.

## Read-only widgets (Phase 3)

The embedded `app.daily-challenge.ios.widgets` extension contains exactly three stable kinds:
`DailyChallenge.Water` (small/medium), `DailyChallenge.Requirements` (medium), and
`DailyChallenge.Extras` (medium/large). It reads only the coordinated active account's local
history. It has no auth composition, network requests, credentials or server configuration.
The extension's version-only build phase reads unchanged `VERSION`; `scripts/ios-archive.sh
--check` verifies embedding, the WidgetKit extension point, bundle ID and matching versions.

**Owner signing steps:** associate the same registered `group.app.daily-challenge.ios` group
with the extension App ID as well as the phone App ID. Regenerate both provisioning profiles
through Xcode automatic signing (or the Apple Developer portal fallback). Before a signed
installation, inspect both profiles' `com.apple.security.application-groups` entitlement and
confirm the same group is authorized. The embedded extension needs no separate App Store
Connect app record. An unsigned archive cannot verify registered capabilities or profiles.

Widget links open Today or Manage extras through the phone's existing auth/setup gating.
Every timeline includes now and three upcoming challenge-zone midnights, derived at each
entry's own date. WidgetKit controls delivery and may retain cached content; refresh is not
promised at an exact midnight. Local commits, adoption/sync, foreground reload and account
changes request fresh timelines. Remote activity requires app execution.

Debug-only `-widget-fixture <variant>` launches use synthetic data in a separate `WidgetFixtures`
group folder and explicitly publish a fixture switch for the independently running extension.
Variants: `empty`, `partial`, `full`, `overflow`, `pending`, `complete`, `missed`, `extras-empty`,
`extras-ten`, `long-names`. Use these only on a disposable simulator. Release contains neither
fixture selection nor seeding. See [Phase 3 evidence](ios-widgets-phase3-evidence.md) for the
reproducible SpringBoard capture procedure and capture provenance.

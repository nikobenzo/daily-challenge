# iPhone app: build, TestFlight and owner steps

The iPhone app (`iOS/`) shares the challenge rules (`ChallengeCore`) and the auth, sync and
reminder code (`ChallengeSyncKit`) with the Mac app, so both clients read and write the same
events. Family members get it through **TestFlight internal testing**, not the App Store.

- Bundle identifier `app.daily-challenge.ios`, team `L644Y3WX5T`, automatic signing.
- Deployment target iOS 26. Sparkle is not linked (the Mac target alone depends on it).
- Its own Keychain items (`app.daily-challenge.ios.auth`), storage under the app's own
  container, and device-local reminder and appearance settings. The same account works on the
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
- **Not in v1:** checklist extras (they sync and appear in History as "Changed"), backups,
  change password, account deletion, widgets.

## One-time owner steps

These need the Apple Developer Program membership (team `L644Y3WX5T`). Nothing here was done
by the worker; no App ID, App Store Connect record, key or upload exists yet.

1. **Xcode account.** Xcode › Settings › Accounts › + › Apple Account: sign in with an account
   that is Admin or Account Holder in the team. (Needed for the app-specific-password route;
   the API-key route signs without it.)
2. **App ID.** Either let the first archive create it (automatic signing with
   `-allowProvisioningUpdates` registers `app.daily-challenge.ios`), or create it yourself:
   developer.apple.com › Certificates, Identifiers & Profiles › Identifiers › + › App IDs ›
   App, explicit Bundle ID `app.daily-challenge.ios`, description "Daily Challenge iPhone". No
   capabilities are needed (background refresh and local notifications need none).
3. **App Store Connect record.** appstoreconnect.apple.com › Apps › + › New App: platform iOS,
   name "Daily Challenge" (App Store names are unique across Apple; if it is taken, choose
   another, such as "Daily Challenge 75": testers see it in TestFlight), primary language
   English (U.K.), bundle ID `app.daily-challenge.ios`, SKU `daily-challenge-ios`, User Access
   Full Access.
4. **Upload credential**, one of:
   - **API key (recommended).** Users and Access › Integrations › App Store Connect API › Team
     Keys › +: name "Daily Challenge uploads", access **App Manager**. Download
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

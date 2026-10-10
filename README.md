# Daily Challenge

A personal native macOS menu-bar challenge tracker, with an iPhone companion app for TestFlight. The agreed product plan is in [PLAN.md](PLAN.md).

**iPhone app:** `iOS/DailyChallenge.xcodeproj` (generated from `iOS/project.yml`, committed) builds a SwiftUI iPhone app sharing `ChallengeCore` and `ChallengeSyncKit` with the Mac: the same account, sync, conflict rules and reminders planner, with Today, History, Account, setup and the sign-in flow. It reaches family through TestFlight internal testing. Build, test, screenshot and TestFlight owner steps: [iPhone app](docs/ios-testflight.md); screenshots in `docs/screenshots/ios/`.

**iPhone extras and widgets.** Extras are optional daily to-dos that never count toward the five or the streak: on Today, tap **Extras · Add your own to-dos** (or Account → Extras) to open Manage extras, add up to 10 one-line titles, rename or archive them, and tick them on Today. To add a widget, touch and hold the Home Screen, tap **Edit → Add Widget**, search **Daily Challenge** and pick **Water** (small or medium: + 450 ml and − to undo today's latest pour), **Daily requirements** (workout, walk, diet and Bible rings; the diet toggles pending ↔ clean) or **Extras** (medium or large, tap a row to tick it). For the Lock Screen, customise it and add the read-only Water ring, which iOS hides while the phone is locked. Widget taps work with the app closed and offline; they are saved on the phone and upload the next time the app runs.

## Current state: functional tracker with production sync

The menu-bar popup now has start-date and timezone setup, a drawn 4 L jug with +450 ml/undo/custom pours, all four habit marks, current/best streaks, valid milestones, and a calendar with explicit historical corrections and an activity audit. It uses the tested **[local foundation](docs/local-foundation.md)**.

**Production challenge sync is implemented; hosted deployment and real two-Mac acceptance are still owner steps.** Follow the [exact migration/install steps and two-Mac checklist](docs/production-sync.md#owner-only-hosted-deployment). Existing local history is backed up and migrated without restarting; logging stays local-first when the backend is unavailable. An empty device checks the server before setup and adopts the existing challenge. Conflicting challenge identities stop sync without replacing either history. The Account tab retains separate diagnostic test messages. Manual JSON export/import is available in Account. See [interface checks](docs/tracker-interface.md).

**Motion:** pours briefly raise and slosh the water; undo lowers it, and overflow adds brief droplets without capping the saved amount. New local daily and 75-day completions receive silent celebrations that do not replay on reopening. System Reduce Motion uses static water and a subtle completion badge instead. See [motion implementation, fixture evidence and pending energy/owner acceptance](docs/motion-verification.md).

**Appearance:** Account → Appearance offers System (default), Light and Dark, applied immediately and saved only on this Mac. The selector is also available before sign-in. See [appearance verification and remaining real-popup checks](docs/appearance-verification.md).

**Launch at login:** Account → Launch at login on this Mac is opt-in, off by default, and device-local (also available before sign-in). Nothing registers automatically. The switch reads macOS status; a pending request stays switchable off and explicitly shows **Requires approval in System Settings > General > Login Items**, not enabled. Errors and missing bundles are shown rather than saving an assumed preference. Ad-hoc-signed builds may need Login Items approval; never bypass security or company policy. The login item points at the app bundle's current location—currently the captain's build folder. After moving or rebuilding to another location, turn it off and back on from the intended bundle. See [fixture evidence and owner checks](docs/login-item-verification.md).

**Water reminders:** Account → Water reminders on this Mac is opt-in and device-local. Choose one Mac, enable, and allow native notifications if offered. Defaults: every 90 minutes, 09:00–21:00 in the challenge's timezone; stop at 4,000 ml including incoming synced water. The app must be running and awake. Permission state and System Settings guidance are shown truthfully. **Native delivery is unverified: the separate ad-hoc fixture was refused authorization on macOS 27.0.1**, including a registered GUI launch. See [owner acceptance and scheduling limits](docs/water-reminders.md#owner-acceptance) and [fixture evidence](docs/notification-fixture-verification.md).

The proof targets **macOS 14 or newer**. The current build uses this Mac's CPU architecture; check the other Mac's architecture and company installation policy before transfer. The current package requires a Swift 6 toolchain to build.

## Supabase preparation

1. The owner applies the production migration once, as described in [production deployment](docs/production-sync.md#owner-only-hosted-deployment) and [Supabase instructions](supabase/README.md), then the [timezone update](docs/production-sync.md#timezone-update-owner-only-once) before installing a build with timezone setup. Automated workers must not apply hosted migrations.
2. For the existing deployment, retain the current Auth user and password login. In-app **Create account** and **Forgot password?** need the owner's custom SMTP (Resend), template and sign-up settings: follow [sign-up setup](docs/sign-up-setup.md#owner-only-dashboard-setup). Until then, password sign-in keeps working and sends no email. For friends and family, share the [getting-started guide](docs/getting-started-for-friends.md).
3. **Fresh accounts only:** in **Authentication → Users → Add user → Create new user**, create a personal app user with an email you control and a strong unique password saved in your password manager. Enable **Auto confirm user**. Creating a user through this form sends no confirmation email.
4. The earlier OTP attempts may have created the original email's Auth user. **Do not delete that user** to clear an 'already registered' error. For a fresh, separate test account, use a Gmail plus alias such as `you+dailychallenge@example.com`; both Macs must then use that exact alias. Existing account data does not migrate to a different user. To keep the original identity instead, arrange an explicit admin password update without sharing credentials in chat.
5. The app password is separate from the Supabase dashboard password, database password, and API keys. Never save it in `.env.local` or send it in chat. Password reset by emailed code works once [sign-up setup](docs/sign-up-setup.md) is complete; until then retain the password in your password manager.
6. Keep the public project URL and publishable key in `.env.local`, using `.env.example` as a reference. Never include a secret/service-role key or database password. Public sign-ups are intended for friends and family; the optional invite-only hook is described in [sign-up setup](docs/sign-up-setup.md#7-later-hardening-optional-only-invited-addresses-can-sign-up). Admin-created users can still sign in.

## Build and launch

From the project folder:

```bash
bash scripts/build-proof.sh
open "build/Daily Challenge.app"
```

Click the **drop-in-circle icon in the menu bar**. There is no Dock icon. The package's standalone `swift run` binary is not the supported launch path; the build script creates the app bundle and embeds public configuration.

The default build is the shareable one: Developer ID signed with the hardened runtime, notarized by Apple, stapled, and zipped to `build/DailyChallenge.zip`. It needs, in `.env.local` or the environment (see `.env.example`):

- `SIGNING_IDENTITY`, the Developer ID Application certificate name from `security find-identity -v -p codesigning` (public, not a secret).
- `NOTARY_PROFILE`, the `notarytool` keychain profile holding the notarization credential (default `dc-notary`). The owner stores it once with `xcrun notarytool store-credentials dc-notary --apple-id <id> --team-id L644Y3WX5T`; the app-specific password lives only in that keychain item, never in the repo or `.env.local`.
- `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_ED_KEY`, the `https://` appcast URL and the public key printed by Sparkle's `generate_keys`, written into Info.plist for automatic updates. The private key stays in the owner's login keychain.

The script stops with a message if any of these is missing; it never silently falls back to ad-hoc. It finishes by requiring `spctl` to report `accepted` with `source=Notarized Developer ID`. Share `build/DailyChallenge.zip` and the [friends guide](docs/getting-started-for-friends.md): a friend unzips, drags the app to Applications, opens it and clicks **Open** on macOS's "downloaded from the internet" dialog, with no System Settings steps, now or for later updates. `--skip-notarize` stops after Developer ID signing and verification (not shareable; no zip is written).

The build embeds Sparkle 2 (`Contents/Frameworks/Sparkle.framework`, signed item by item before the app), so installed copies check daily for updates and offer them in Sparkle's window; **Account › About › Check for updates** checks on demand. To publish a version: bump `VERSION`, run `bash scripts/build-proof.sh`, then `bash scripts/release.sh`, which stages `releases/appcast.xml` and the zip for upload without uploading anything. The feed host is still to be chosen. See [releases](docs/releases.md) for the one-time key setup and the full steps.

For local development, `bash scripts/build-proof.sh --adhoc` keeps the old ad-hoc signature (the Sparkle values are optional; without them updates are off) and prints a notice that the result is **not shareable**: Gatekeeper blocks it on other Macs, and it may need Login Items approval. Do not disable Gatekeeper or bypass company controls.

The first launch after switching between an ad-hoc and a Developer ID build (or the reverse) changes the app's code identity, so macOS may ask once whether Daily Challenge may use its saved Keychain item; choose **Always Allow**, or sign in again if the session does not restore. The Keychain identifiers themselves are unchanged.

The output is now `build/Daily Challenge.app` (version 0.2). The executable target, bundle identifier, Keychain service, and proof caches retain their old names to preserve identity. Quit the older proof before opening this app; do not run both. Old `Daily Challenge Proof.app` / `DailyChallengeProof.zip` artifacts are legacy proof builds.

## First-Mac tracker checks

1. Quit the old proof and open `build/Daily Challenge.app`. Click the menu-bar drop icon. If your session does not restore, sign in with the same app account.
2. Existing local history migrates automatically with a timestamped backup; **do not restart the challenge**. An empty device first checks the server and adopts an existing challenge. Only if the server has none may you select the actual start date and your timezone (it defaults to this Mac's; search for your city) and click **Start challenge**. Every challenge day runs midnight to midnight in that timezone, including daylight saving, wherever the Mac is; neither the start date nor the timezone can be changed afterwards. Challenges started before this choice existed stay on Europe/Jersey. New setup waits if the backend is unavailable. Past unrecorded days are missed until corrected.
3. Add water (**+ 450 ml**), try a custom amount (**⋯**), and undo (**−**). Nine standard pours show 4,050 ml. Click the workout, walk and Bible rings to toggle; the diet ring cycles pending → clean → missed, with a right-click menu for direct selection.
4. Open **History** (calendar icon), select a tracked date, then the pencil (**Edit this day**) to unlock its controls; it turns amber while the day is editable. Changes save immediately and recalculate streaks. The day's **Activity** list is below; it scrolls inside. Merely selecting a day never changes it.
5. Quit and reopen. Check that your challenge, water entries, and corrections return. Check light/dark appearance, keyboard navigation, VoiceOver labels, and Reduce Motion.
6. Check the challenge footer: waiting/checking, locally saved pending work, unavailable/error, or timestamped synced. Click the footer's sync status to sync immediately (its tooltip has the full status). A clock/delivery warning means a client timestamp differed from server receipt by more than five minutes; delayed offline delivery can also cause it.

## Personal-data backups

1. In **Account → Your data**, choose **Export** and a private save location. Exports contain personal data: account/challenge IDs, the immutable start date and timezone, and all activity and corrections. Exports are format version 3, which can hold [extras](docs/tracker-interface.md#daily-checklist-extras); version-2 files still import, and version-1 files from earlier builds import as Europe/Jersey challenges. Apps from before extras refuse a version-3 file as an unsupported version, changing nothing. They contain no credentials, session tokens, derived counters, or device-local appearance/reminder settings. Optional diet-rule text is not implemented yet.
2. Sign into the **same app account**. If this device has no local challenge, let it adopt the existing challenge through sync before importing; a device that already has that challenge can import offline. Choose **Import** and the exported file. Review the new/duplicate activity counts, then confirm **Import and merge** (or cancel). Malformed, unsupported-version, wrong-owner, mismatched-challenge (including a different timezone) and conflicting-ID files are rejected without changing history. This is not a cross-account restore or a way to create/replace a challenge.
3. A timestamped `challenge-<owner>.json.backup-<timestamp>-<uuid>` recovery copy is saved beside local storage **before** applying the merge; failure stops the import. The success message shows its path. These recovery snapshots also contain personal data; retain them privately. They are internal storage snapshots, not portable export files—do not overwrite current storage or import them through this UI.
4. Existing activity is never deleted. Re-importing adds no duplicates; new records enter the normal durable sync queue, and totals, streaks and milestones recalculate. Check the challenge footer for delivery status; offline imports remain pending until sync succeeds. Historical edits retain their original ordering, so an older imported mark need not override a newer local correction.

Automated fixture coverage includes round trips, rejection/preservation, backup failure, undo history, derived milestones, durable queuing and response-loss retries. Native save/open/confirmation panels still need owner acceptance in the real popup: verify export, import preview, **Cancel changes nothing**, and confirmed re-import adds no duplicates, using an isolated account. Tests do not install or replace the running app.

## Account / sync-diagnostics checks

The signed-in Account tab is one plain-language grouped list: You (email, day count and start date), Sync (the footer's status in plain words, with Sync now), Reminders, Appearance & startup, Your data, Account (Change password, which opens an inline new-password form; Sign out), About (version and Check for updates) and a collapsed **Advanced** disclosure holding the test-message diagnostics below. See [fixture renders](docs/screenshots/account-tab/).

1. Quit any running older proof app before reopening the rebuilt app.
2. Enter the manually provisioned app user's email and password and click **Sign in**. No email link/code is sent. The password field clears after each attempt; only session tokens persist in Keychain.
3. Open **Advanced** at the bottom of Account and add a test entry. Click Sync now if needed; the entry should change from pending to confirmed.
4. Quit and reopen; confirm the session and history return. Session storage is explicitly Keychain-backed; local entries contain no tokens.
5. Turn on **Pause sync**, add an entry, quit, and reopen. Pause is a temporary test toggle and resets on relaunch; immediately pause again if you want to keep testing without uploads. The durable pending entry should still exist. For a real offline test, disconnect the network before relaunch.
6. Reconnect/resume and sync. The pending entry should be confirmed once without duplication. If an upload succeeds but the response is lost, the stable entry ID makes retry safe.

## Two-Mac checks (after installation approval)

For real water/habit history, follow the [production acceptance checklist](docs/production-sync.md#two-actual-macs-owner-acceptance-checklist). Deploy the schema and sync the Mac containing the real challenge first. These older checks below are **diagnostic test-message checks only**, not production-sync acceptance:

- Sign into the same app email on both Macs, not separate app users.
- Add a uniquely labeled message on each; sync or wait for the 30-second polling interval. Both lists must converge.
- Pause sync/disconnect both, add one message on each, reconnect/resume, and confirm both records survive exactly once.
- Sign out on one Mac and verify that the other remains signed in. Local scope sign-out is used; pending files are preserved and account-separated.
- Check actual network failure, sleep/wake, and relaunch with pending work. Realtime is not required for this proof.

## Local verification

```bash
swift test
bash scripts/test-sync-security.sh
```

The Swift tests cover production merge/convergence, same-pour undo, migration backups, clock-skew boundaries, offline pending relaunch, account-switch races, intercepted SDK batching/pagination and expired sessions, alongside the challenge foundation, UI-to-storage actions/failures, production-root appearance backing, native surface rendering, and durable diagnostic queues. PostgreSQL tests verify grants/RLS with a minimal local stand-in for Supabase Auth. SDK authentication tests exercise the actual SDK password-login request with an intercepted transport, including email normalization, preserving password whitespace, clearing the form after success/failure, and retaining local-file errors. These never use real credentials or Keychain. Hosted password login/JWT validation, Keychain runtime behavior, and true two-Mac reconciliation still require manual acceptance.

Real challenge data lives under `~/Library/Application Support/DailyChallenge/ujyvvyrugenknhjodfhc/`, with one versioned challenge-history JSON file per app account and a separate [device-local celebration ledger](docs/motion-verification.md#implementation). Version 2 atomically includes its pending production queue; version-1 migration first makes a timestamped backup alongside the original. It is not uploaded by the diagnostics queue. Do not delete/reset files to resolve a UI, authentication, or challenge-conflict error.

Local proof data lives under `~/Library/Application Support/DailyChallengeProof/<project>/`, separated by user ID. Do not delete a queue with pending work. Uploaded test entries are append-only; resetting them requires an explicit admin action, not a client delete control.

## Architecture

- `Sources/ChallengeCore/`: challenge rules, convergent event merge, versioned durable queue/storage, and transport seam; no SDK or UI dependency.
- `Sources/ProbeCore/`: durable account-scoped test journal; no SDK or UI dependency.
- `Sources/ChallengeSyncKit/`: platform-neutral library shared by the Mac and iPhone apps: Supabase transport, the sync coordinator and its status (`TrackerModel`), email/password/code authentication (`AuthModel`), water-reminder scheduling, challenge-zone dates and the finite motion clocks. Depends only on `ChallengeCore` and `supabase-swift`; no AppKit, UIKit, Sparkle or popup code.
- `Sources/DailyChallengeProof/`: the Mac menu-bar app: popup, views, Sparkle updates, login item, the Mac's reminder lifecycle and the separate proof-sync diagnostics, consuming the kit. Its `Shared/` folder (design tokens, ring gauge, jug, completion effect, buttons and badges) also compiles into the iPhone app, so it must stay free of AppKit and UIKit.
- `iOS/`: the iPhone app (`project.yml`, the generated Xcode project, `DailyChallenge/` sources, the `DailyChallengeWidgets/` WidgetKit extension and its App Intents, `Shared/` storage and widget actions, unit and UI tests, and the configuration build phase); `scripts/ios-archive.sh` archives and uploads it for TestFlight.
- `supabase/migrations/`: versioned database changes.
- `Tests/ChallengeCoreTests/`, `Tests/ChallengeSyncKitTests/`, `Tests/TrackerInterfaceTests/`, `Tests/ProbeCoreTests/`, `Tests/ProofAuthTests/`, and `supabase/tests/`: automated local checks.

The diagnostics remain independent of production activity. See [production sync architecture and deployment](docs/production-sync.md). Remaining work includes owner-hosted deployment/two-Mac acceptance, native reminder delivery and backup-panel acceptance, [motion energy/owner acceptance](docs/motion-verification.md), and validated distribution. No cloud CI is configured.

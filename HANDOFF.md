# Daily Challenge — Agent Handoff

Updated: 9 October 2026. Project: the owner's clone of this repository.

## Start here: production sync implemented; owner deployment and two-Mac acceptance next

**Implementation update (8 October):** after the merged appearance fix, production challenge sync is implemented with isolated fixture/SDK/PostgreSQL verification. **No hosted migration, real-data access, installation, or actual two-Mac acceptance was performed by the worker.** Read [production sync](docs/production-sync.md) for policies, architecture, and limitations.

### Next task and completion criteria

The owner must follow the [exact hosted migration/install steps](docs/production-sync.md#owner-only-hosted-deployment) and [two-Mac acceptance checklist](docs/production-sync.md#two-actual-macs-owner-acceptance-checklist). Deploy the new migration once, sync the Mac containing the real challenge first, then let the second Mac adopt it. Preserve the existing login, start date, 900 ml plus later entries, and identifiers below. Never reset history to resolve a conflict. No cloud CI is configured.

Appearance backing and the device-local setting remain implemented; [appearance verification](docs/appearance-verification.md) still distinguishes in-process renders from real-popup acceptance. Automated testing must never quit or replace the running app.

## iPhone app, phase 8 (9 October)

**8a:** `ChallengeSyncKit` (SwiftPM library) now holds the Supabase transport, the sync coordinator and `SyncState` (`TrackerModel`), auth (`AuthModel`, taken out of `ProofModel`), the reminder controller, challenge dates and motion clocks; it depends only on `ChallengeCore` and `supabase-swift`. Each app supplies its lifecycle, Keychain names (`SessionStorage`) and wording (`DeviceWording`). The Mac's `ProofModel` is now its account object (kit auth under the unchanged legacy Keychain names, plus the diagnostics journal); identifiers, paths and data are unchanged. Tests: `Tests/ChallengeSyncKitTests/`.

**8b:** `iOS/` is a SwiftUI iPhone app (`app.daily-challenge.ios`, team `L644Y3WX5T`, iOS 26, no Sparkle) with sign-in/create/code confirmation/reset, setup with timezone (only after a successful server check; otherwise the existing challenge is adopted), Today, History (Edit this day), and Account (sync, water reminders, appearance, sign out on this iPhone), using the shared design tokens and components in `Sources/DailyChallengeProof/Shared/`. Sync runs on launch, foreground, while open, after edits and in `BGAppRefreshTask`; reminders queue the remaining slots of today and tomorrow (`ReminderPolicy.queued`) because a suspended app cannot schedule the next one. Extras sync but are not shown (History reads them as "Changed"). Configuration comes from `.env.local` at build time. **Owner steps:** App ID, App Store Connect record, upload credential, internal "Family" group, then `scripts/ios-archive.sh` per build ([iPhone app](docs/ios-testflight.md)). **Verified only in the iPhone 17 simulator on fixtures and fake transports; no App Store Connect record, upload, real device or real account was used.** Screenshots: `docs/screenshots/ios/`.

## Daily checklist extras (9 October)

Roadmap phase 7, Mac only (the iPhone app adopts the same events later). Personal daily to-dos beside the five requirements; per captain decision D7 they **never count toward a complete day or the streak** (`isComplete`, streaks and milestones ignore them). Today shows a collapsible **Extras** checklist under the rings, hidden when no extras exist, with a one-time "All extras done!" celebration through the non-replaying ledger; History's day card gets an extras pill whose ticks follow the habit correction rules; **Manage extras** (from the Today section header and **Account → Extras**) adds, renames and archives, at most 10 active. Three new `Action` cases, `defineExtra(id:title:)`, `archiveExtra(id:)` and `setExtra(id:completed:)`, sync through the unchanged transport; `Challenge.allExtras`/`extras(asOf:)` and `DailySummary.extras`/`completedExtras`/`extrasDone`/`extrasTotal` derive the list. [Behaviour, wire format and validation](docs/tracker-interface.md#daily-checklist-extras); views in `ExtrasViews.swift`, model calls in the extras section at the end of `TrackerModel.swift`.

**Decisions (firstmate, 9 October):** (1) the roadmap's "no migration" predates the abuse-limit action-kind allowlist, so the owner applies the additive `20261010000100_extras_action_kinds.sql` once, after abuse limits and **before releasing this build** ([extras update](docs/production-sync.md#extras-update-owner-only-once)); until then an uploaded extras event is rejected and holds its upload batch, with nothing lost. (2) `merge` rejects only extras events for an extra never defined anywhere in the union (and invalid names); archives are order-independent and permanent, and a tick on an archived extra from another Mac is kept, because rejecting it would stop sync for both Macs. This Mac's own edits (`record`) still refuse ticks on archived or undefined extras.

**Legacy compatibility:** clients from before extras cannot decode the new events. Builds that skip unreadable server rows report them as skipped and keep syncing everything else; older builds stop syncing; a local snapshot containing extras cannot be opened by them (nothing is reset); and exports are now **format version 3**, which they refuse as an unsupported version. So every Mac must auto-update before extras are used. Tests: two-Mac define/rename/archive/tick convergence with clock order and archive races, the "extras never change `isComplete`" invariant, merge rejections, cap and title rules, backup v3 round trip and v2 import, the wire format, the celebration ledger, and Light/Dark fixture renders (`docs/screenshots/appearance-fixtures/*extras*`) plus a real-popup capture (`docs/screenshots/real-popup/today-extras-*.png`). **No hosted migration was applied and no running app, real data or Keychain was touched.**

## Visual redesign (9 October)

Every screen now follows the captain-approved Paper design system: a 420 pt glass sheet with hairline sections, a detached footer capsule, five ring gauges on Today, an icon-only section switcher, icon-first controls with tooltips, and animated (never cut) height changes; History and Account share one height. [Design system](docs/design-system.md) lists the tokens (`Theme.swift`), components, window-height policy and the board ambiguities decided in code. Presentation only: behaviour, sync, auth, reminders, backups, updates and timezone logic are unchanged. Regressions: `productionPopupSurfacesHaveAdaptiveGlass`, `signedOutAuthScreensHaveAdaptiveGlass`, `PopupResizeTests`. **Popup fix (9 October):** on macOS 27 the `MenuBarExtra` window was 298 pt wide, kept stale heights and drew a system backdrop, so the captain saw a cut, banded popup. The popup is now the app's own status item and transparent panel (`PopupWindow.swift`; [decision](docs/design-system.md#popup-window)), with the boards' sheet and footer shadows. `scripts/capture-real-popup.sh` opens and captures the real popup of an isolated copy without a click ([probe](docs/appearance-verification.md#real-popup-probe)); captures of every screen in both appearances and the animated resize traces are in `docs/screenshots/real-popup/`. Remaining captain checks: blur over the real desktop, outside-click/Escape closing, typing, popovers, a second display.

## Per-challenge timezone (9 October)

Each challenge now has an immutable IANA timezone, chosen at setup next to the start date and synced like it; every day boundary, streak, milestone, reminder window, midnight refresh and displayed date follows it instead of a fixed Europe/Jersey. Setup (`TrackerView.setup`, `TimeZonePicker.swift`) defaults to the Mac's zone with a searchable, region-grouped list showing each identifier and its current offset; adopting an existing challenge never shows it. `ChallengeDates.swift` (formerly `JerseyDates.swift`) is the per-challenge display/navigation helper. Europe/Jersey survives only as the default for legacy data: v2 snapshots and server rows without a zone, and version-1 exports (exports are now format 2). A zone-only settings difference is a conflict under the existing rule.

**Owner step:** apply `20261009000100_challenge_time_zone.sql` once before installing this build ([timezone update](docs/production-sync.md#timezone-update-owner-only-once)); the existing row becomes Europe/Jersey. Until then an existing challenge still syncs, and only a new challenge's settings upload shows "the server needs the timezone update". Tests: zone-parameterised boundaries/DST/streaks (Jersey, New York, Sydney, GMT), record/snapshot/backup decoding across versions, zone-only conflicts, non-UK reminder planning, intercepted unmigrated-server SDK requests, and a PostgreSQL seed proving the default on a pre-existing row. Setup renders: `docs/screenshots/time-zone/`. **No hosted migration was applied and no running app, real data or Keychain was touched.** This ships to users only after automatic updates are live (firstmate's sequencing).

## Automatic updates implementation (9 October)

Sparkle 2.10.0 (pinned) gives installed copies daily update checks and in-app installs; **Account › About › Check for updates** checks on demand. `SoftwareUpdates.swift` owns the single `SPUStandardUpdaterController`, activates the Dock-less app before Sparkle shows a window, and leaves later background finds in About ("Version X is available", **Install update**) rather than taking focus. It never starts when Info.plist lacks `SUFeedURL`/`SUPublicEDKey`. `scripts/build-proof.sh` writes those from `.env.local` `SPARKLE_FEED_URL`/`SPARKLE_PUBLIC_ED_KEY` (required unless `--adhoc`), embeds `Sparkle.framework` without the sandbox-only XPC services, strips SwiftPM's build-folder rpaths and signs Sparkle's nested code explicitly before the app. `scripts/release.sh` stages `releases/appcast.xml` plus the version-named zip for upload and uploads nothing. [Owner steps](docs/releases.md); [evidence](docs/update-verification.md).

**Open owner decisions and steps:** choose the HTTPS feed host (the repository is private), run `generate_keys` once (the private key stays in the login keychain), put the feed URL and public key in `.env.local`, and hand-install the first update-capable build on every Mac (0.2.0 has no updater). The worker used only a throwaway file key and a 127.0.0.1 feed; **no key was added to any keychain, nothing was uploaded except to Apple's notary service, and the running app was not touched.**

## Self sign-up and password reset (8 October)

The signed-out popup (`AuthView.swift`) offers Sign in, Create account and Forgot password, each code step with a 60-second Resend code countdown. `ProofModel` adds `signUp`, `confirmSignUp`, `requestPasswordReset`, `completePasswordReset`, `resendCode` and `changePassword(new:)`, which backs the Account tab's Change password row (inline form, fixture `docs/screenshots/account-tab/account-tab-change-password-*.png`). A nil session after sign-up means "code required". [Owner checklist, SDK mapping and known behaviour](docs/sign-up-setup.md); [friends guide](docs/getting-started-for-friends.md). Tests are intercepted-transport only; **no hosted sign-up, dashboard change or real email send was performed**. Owner acceptance is the checklist's step 6.

## Water reminders implementation (8 October)

Water-only reminders are implemented. See [README usage](README.md) and the [scheduling contract, limitations and owner checks](docs/water-reminders.md), including target-day eligibility for midnight slots.

**Native delivery remains unverified:** the isolated ad-hoc fixture on macOS 27.0.1 returned `UNErrorDomain` code 1, including the bounded registered GUI-launch diagnostic. This does not prove signing is the root cause. Firstmate authorized implementation with truthful permission state, not signing/security changes. [Evidence](docs/notification-fixture-verification.md) must be retained in the PR. Owner acceptance: choose one Mac, enable in Account, allow native permission if offered, inspect System Settings > Notifications if denied, then verify actual delivery/completion/undo/sleep/synced completion. Neither fixture tests nor an enabled toggle prove native delivery. No cloud CI.

## Launch at login implementation (8 October)

Account offers opt-in, device-local launch at login using `SMAppService.mainApp`; startup only reads status, never registers. Enabled, approval-required, missing and failed states are surfaced. The login item targets the current bundle location (currently the captain's build folder); moving or rebuilding to another location requires re-toggling from the intended app. Ad-hoc-signed apps may require approval in System Settings > General > Login Items. Do not bypass security/company restrictions. [Fixture evidence and owner acceptance](docs/login-item-verification.md): isolated fixture registration/unregistration passed; no real-app login item was changed and actual login launch remains owner acceptance.

## JSON backup implementation (8 October)

Account → Backups now exports portable version-1 JSON and previews/ confirms same-account, same-challenge ID-based imports. See [user steps and personal-data warning](README.md#personal-data-backups). `ChallengeBackup.swift` owns pure encoding/validation/planning; `ChallengeStore` uses the migration recovery-copy mechanism before atomic import and queues new immutable events for normal sync. Re-imports do not duplicate or acknowledge pending entries. Settings are the immutable challenge identity/start date, not device-local preferences; optional diet-rule text remains unimplemented. Empty devices must adopt through sync before import. No cross-account restore or destructive replacement.

Fixture tests cover validation, round trips, undo, derived recalculation, backup-before-apply/failure and normal sync retries. Actual native panels/popup interaction remain owner acceptance; no real files, Keychain or running app were accessed.

## What exists now

- **Native SwiftUI menu-bar app**, no normal Dock icon/main window. Running bundle: `build/Daily Challenge.app`, version **0.2.0**. Archive: `build/DailyChallenge.zip`.
- **Setup:** authenticated account, server adoption/preflight, explicit start-date and timezone choice only when no challenge exists, all five requirements explained. Setup cannot overwrite an existing challenge.
- **Today:** drawn 4 L jug, uncapped actual ml count, +450 ml, latest-active-pour undo, custom positive whole-ml pours; reversible workout/walk/Bible marks; pending/clean/missed diet cycle and direct context-menu selection.
- **Streaks:** current / 75, best, and valid milestone count. Tracking continues beyond 75.
- **Extras:** optional personal daily to-dos (at most 10 active) in a collapsible Today checklist, History corrections and Manage extras; never part of a complete day.
- **History:** monthly Monday-first calendar, day-state symbols, explicit **Edit this day** (pencil) unlock, immediate selected-day corrections, and newest-first activity audit, which scrolls inside the fixed History height. Selection is not an edit; selecting another date exits correction mode.
- **Account:** retained email/password authentication and separate test-message sync diagnostics.
- **Bounded motion:** procedural rise/fall, settling slosh and clipped overflow; daily/75-day celebrations consumed in a separate device-local ledger, never replayed from open/sync/import. Reduce Motion uses static levels and a brief completion badge. [Fixture CPU evidence and owner checks](docs/motion-verification.md); the final 60-second settled fixture run became occluded, so final energy and real-popup motion acceptance remain pending.

**Real challenge activity now has its own production queue and sync coordinator.** The footer shows pending/synced/error state and clock/delivery warnings. Until the owner deploys the schema, existing history remains locally usable with sync errors; an empty device waits for a successful server check before setup. Diagnostic test-message sync remains independent.

### Implementation map

| Location | Role |
| --- | --- |
| `Sources/ChallengeCore/Challenge.swift` | UI/network-independent rules, deterministic event union/undo reconciliation, day summaries, derived streaks/milestones and the extras list |
| `Sources/ChallengeCore/ChallengeStore.swift` | Account-scoped atomic history + pending queue, v1 backup/migration, exact acknowledgment; corrupt files throw rather than reset |
| `Sources/ChallengeCore/ChallengeSync.swift` | Immutable challenge settings/event wire records and injected transport seam |
| `Sources/ChallengeSyncKit/` | Platform-neutral library shared by the Mac and iPhone apps (depends on `ChallengeCore` and `supabase-swift` only); tests in `Tests/ChallengeSyncKitTests/` |
| `Sources/DailyChallengeProof/Shared/` | Design tokens and components compiled into both the Mac target and the iPhone app (no AppKit/UIKit beyond Theme's colour and font helpers) |
| `iOS/` | The iPhone app: `project.yml` (XcodeGen) and the committed `DailyChallenge.xcodeproj`, sources, unit/UI tests, `scripts/bundle-configuration.sh` and `scripts/capture-screenshots.sh` ([iPhone app](docs/ios-testflight.md)) |
| `Sources/ChallengeSyncKit/SupabaseChallengeTransport.swift` | Authenticated insert-ignore batches, owner-scoped paginated reads; proof-style transport |
| `Sources/ChallengeSyncKit/TrackerModel.swift` | Main-actor UI/sync coordinator and `SyncState`, account generations, backoff, setup preflight and truthful status; one active writer |
| `Sources/ChallengeSyncKit/AuthModel.swift` | Supabase email/password auth with emailed codes, Keychain sessions under per-app names (`SessionStorage`), bundled public configuration |
| `Sources/ChallengeSyncKit/WaterReminderController.swift`, `ChallengeDates.swift`, `TrackerMotion.swift`, `DeviceWording.swift` | Reminder reconciliation (each app drives sleep/wake), dates and zone choices in the challenge's zone, finite motion clocks and celebration ledger, per-device wording ("this Mac") |
| `Sources/DailyChallengeProof/Shared/Theme.swift`, `Shared/SharedComponents.swift`, `Components.swift`, `PopupWindow.swift` | Design-system tokens, shared glass components, the status item and transparent popup panel with its animated height ([design system](docs/design-system.md)); `PopupProbe.swift` is the developer-only real-popup probe |
| `Sources/DailyChallengeProof/TrackerView.swift`, `TodayView.swift`, `TimeZonePicker.swift` | Root sheet, header, footer and setup with its timezone picker; Today rings, water and streak; visible-window/midnight/wake refresh; dates in the challenge's zone |
| `Sources/DailyChallengeProof/Shared/WaterJugView.swift`, `Shared/CompletionEffect.swift`, `PopupVisibility.swift`, `MacPlatform.swift` | Finite motion schedules, local celebration ledger, noninteractive effects and native visibility gating |
| `Sources/DailyChallengeProof/HistoryTrackerView.swift` | Calendar, correction unlock, audit |
| `Sources/DailyChallengeProof/ExtrasViews.swift` | Today's Extras section, History's extras pill, Manage extras popover and Account row |
| `Sources/DailyChallengeProof/DailyChallengeProofApp.swift`, `AuthView.swift` | App entry (models, `PopupController`; drop.circle, filled while open); signed-out sheet (`ProofView`) and auth steps |
| `Sources/DailyChallengeProof/AccountView.swift`, `AdvancedDiagnosticsView.swift` | Signed-in Account tab as hairline-separated settings rows; sync line rephrases `TrackerModel.syncState` (same source as the footer); test-message diagnostics moved unchanged behind a collapsed Advanced disclosure |
| `Sources/DailyChallengeProof/SoftwareUpdates.swift` | Sparkle updater, Dock-less window activation, About-group update row |
| `Sources/DailyChallengeProof/ProofModel.swift` | The Mac's account object: `AuthModel` under the legacy Keychain names, plus the proof queue/polling diagnostics; not production challenge sync |
| `Sources/ProbeCore/ProbeJournal.swift` | Durable independent test-message queue, retry IDs, validated remote acknowledgments |
| `supabase/migrations/`, `supabase/tests/` | Proof + production append-only schema and local role/RLS/child-ownership tests |

## Data and identity: preserve these

The user now has **real local records**, not only fixtures.

- Challenge files: `~/Library/Application Support/DailyChallenge/ujyvvyrugenknhjodfhc/challenge-<owner-uuid>.json`.
- Separate proof queues: `~/Library/Application Support/DailyChallengeProof/ujyvvyrugenknhjodfhc/<owner-uuid>.json`. Pending messages must survive.
- Bundle ID **`app.daily-challenge.proof`**, executable/Swift target **`DailyChallengeProof`**, Keychain service **`app.daily-challenge.proof.auth`**, and auth storage key **`daily-challenge-proof-ujyvvyrugenknhjodfhc`** intentionally retain legacy names for continuity. The visible product/bundle filename is now Daily Challenge.
- `build/Daily Challenge Proof.app` and `build/DailyChallengeProof.zip` are older artifacts. Use the new app/archive. Quit older/running versions before reopening; avoid simultaneous writers for the same account.
- Use temporary fixture accounts/directories for testing. Preserve live files; back them up before any future storage migration. Fixing theme must not require resetting setup or deleting data.

## Verification and build

See [appearance verification](docs/appearance-verification.md#automated-verification) for the recorded results and packaging limitation. User acceptance confirms opening and +450 ml twice, not all controls, relaunch durability, or correct themes.

```bash
swift test
bash scripts/test-sync-security.sh
bash scripts/build-proof.sh
bash scripts/capture-real-popup.sh   # after an --adhoc build; isolated copy, see docs/appearance-verification.md
bash scripts/test-update-fixture.sh --ed-key-file <throwaway key>  # isolated Sparkle probe, see docs/update-verification.md
# Quit the running older app first, then:
open "build/Daily Challenge.app"
```

Optional isolated visual fixtures:

```bash
DAILY_CHALLENGE_SNAPSHOT_DIR=/tmp/daily-challenge-interface-previews \
  swift test --filter nativeTrackerSurfaces
```

After a changed build, refresh the transferable archive if needed:

```bash
ditto -c -k --sequesterRsrc --keepParent "build/Daily Challenge.app" build/DailyChallenge.zip
```

The build script embeds **public** configuration from `.env.local`; standalone `swift run` is not the supported configured launch path. The package uses Swift 6, macOS 14 minimum, pinned `supabase-swift` 2.55.3 and pinned Sparkle 2.10.0.

## Product invariants

- All five daily requirements: **4,000 ml water, 45-minute workout (home/gym), 45-minute walk, clean diet, 10 Bible pages**. Non-water activities are self-certified; no rest-day exemptions or invented food rules.
- Every day is defined by the **challenge's own timezone** (chosen at setup; Europe/Jersey for challenges and data that predate it), including DST, independently of device timezone. Earlier-than-start and future dates cannot be completed. Unrecorded closed tracked dates are missed.
- Incomplete or explicitly missed **today** preserves the consecutive complete run through yesterday until midnight. Add today when complete. Corrections recalculate current/best streaks and valid 75-day milestones from history.
- Each pour has a stable ID; undo references a specific pour, not a mutable total. Keep correction history. Local command retries require the original ID and edit timestamp.
- Local snapshot storage has one serialized writer per account/device. Production ordering is client timestamp → device ID → event ID; server receipt never reorders edits. A >5-minute receipt/client difference warns without dropping edits (offline delay also qualifies). Independent pours union; duplicate undos target one pour. Full immutable event history prevents resurrection.
- Shared settings (start date and timezone) are immutable. Empty devices check the server/adopt before setup; offline new setup waits. Different challenge identities/settings stop sync and preserve both histories. There is no conflict-resolution UI in this increment.

## Backend and outstanding acceptance

Supabase replaced CloudKit because the Apple Developer membership was inactive at the time (it is now active, for Developer ID signing only) and the Macs use different iCloud accounts. Both Macs will use the same app login. Public client configuration lives in `.env.local` (template `.env.example`); no admin key/password is needed by the app.

- Password login works on the first Mac. The 2025 SMTP/OTP attempt failed on an unverified Resend domain; in-app sign-up and password reset by emailed code (8 digits documented; the app accepts 6 to 10) are now implemented over custom SMTP but need the [owner dashboard steps](docs/sign-up-setup.md#owner-only-dashboard-setup). Retain the existing Auth user. Passwords are not persisted; sessions use Keychain.
- Proof table `public.sync_probe_entries`: authenticated owner-only SELECT/INSERT, anonymous denied, client UPDATE/DELETE denied. Local RLS checks and a prior hosted anonymous-denial check passed; an actual uploaded test message was confirmed.
- Both Macs are **Apple Silicon, macOS 27.0.1 (26A434)**. Work policy permits the app. Home-Mac/two-Mac verification was explicitly deferred by the user, not passed.
- Keychain persistence after real relaunch, true offline recovery, all-interface/accessibility acceptance, and real two-Mac reconciliation remain manual/unproven.
- `scripts/build-proof.sh` builds are **Developer ID signed (team `L644Y3WX5T`), hardened runtime, notarized and stapled** by default, read `SIGNING_IDENTITY`/`NOTARY_PROFILE` (default keychain profile `dc-notary`) from the environment or `.env.local`, and refuse to fall back to ad-hoc; `--adhoc` is the explicit local-only path. Shareable builds also require `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_ED_KEY` ([releases](docs/releases.md)). No entitlements are used. [Verification](docs/notarization-verification.md). Preserve security controls. Paid memberships/subscriptions or deployment-policy bypasses require user approval. Keep credentials out of chat/docs; do not request service-role keys or delete Auth users to work around login issues.

## Roadmap and remaining acceptance

Work in separate verifiable increments; do not treat fixture success as owner/device acceptance:

1. **Production challenge sync — implementation complete, acceptance pending:** owner-protected migration, real activity/start-date sync, durable offline queue, idempotent retries, deterministic conflicts/undo, and pending/synced/error state. Version 1 is backed up before migration. Owner-hosted deployment and both actual Macs still need the [checklist](docs/production-sync.md#two-actual-macs-owner-acceptance-checklist).
2. **Settings/reminders/backups:** water reminder and opt-in launch-at-login implementations complete, native reminder delivery and owner checks pending (see above); validated JSON export/import with recovery backup implemented (native panel acceptance pending).
3. **Animation implementation complete; energy/owner acceptance pending:** bounded pour/slosh/undo/spill, non-replaying local daily/75-day celebrations and live Reduce Motion fallback. Fixture CPU measurements are recorded, but final settled-idle comparison is incomplete because the fixture became occluded. See [motion verification](docs/motion-verification.md) for exact numbers, remaining energy validation, and real-popup/VoiceOver/contrast/two-Mac checks. Optional dated diet-rule text is still deferred.
4. **Daily checklist extras — implementation complete; owner migration and acceptance pending:** apply the [extras update](docs/production-sync.md#extras-update-owner-only-once) before releasing, then on two Macs add, rename, archive and tick extras (including one ticked offline on one Mac while archived on the other) and confirm both converge and that no day's completion or streak changes.

For UI/storage details, read [tracker interface](docs/tracker-interface.md) and [local foundation](docs/local-foundation.md). Before sync work, read [sync/storage plan](plans/sync-and-storage.md) and [Supabase instructions](supabase/README.md). Before reminder or distribution work, read the corresponding documents under [the overall plan](PLAN.md). These describe intended scope; this handoff records the latest user report and immediate priority.

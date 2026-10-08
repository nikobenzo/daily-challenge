# Daily Challenge — Agent Handoff

Updated: 8 October 2026. Project: `the owner's clone`.

## Start here: production sync implemented; owner deployment and two-Mac acceptance next

**Implementation update (8 October):** after the merged appearance fix, production challenge sync is implemented with isolated fixture/SDK/PostgreSQL verification. **No hosted migration, real-data access, installation, or actual two-Mac acceptance was performed by the worker.** Read [production sync](docs/production-sync.md) for policies, architecture, and limitations.

### Next task and completion criteria

The owner must follow the [exact hosted migration/install steps](docs/production-sync.md#owner-only-hosted-deployment) and [two-Mac acceptance checklist](docs/production-sync.md#two-actual-macs-owner-acceptance-checklist). Deploy the new migration once, sync the Mac containing the real challenge first, then let the second Mac adopt it. Preserve the existing login, start date, 900 ml plus later entries, and identifiers below. Never reset history to resolve a conflict. No cloud CI is configured.

Appearance backing and the device-local setting remain implemented; [appearance verification](docs/appearance-verification.md) still distinguishes in-process renders from real-popup acceptance. Automated testing must never quit or replace the running app.

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
- **Setup:** authenticated account, server adoption/preflight, explicit Jersey start-date choice only when no challenge exists, all five requirements explained. Setup cannot overwrite an existing challenge.
- **Today:** drawn 4 L jug, uncapped actual ml count, +450 ml, latest-active-pour undo, custom positive whole-ml pours; reversible workout/walk/Bible marks; pending/clean/missed diet cycle and direct context-menu selection.
- **Streaks:** current / 75, best, and valid milestone count. Tracking continues beyond 75.
- **History:** monthly Monday-first calendar, day-state symbols, explicit **Edit this day** unlock, immediate selected-day corrections, and newest-first activity audit. Scroll to reach all controls/audit. Selection is not an edit; selecting another date exits correction mode.
- **Account:** retained email/password authentication and separate test-message sync diagnostics.
- **Bounded motion:** procedural rise/fall, settling slosh and clipped overflow; daily/75-day celebrations consumed in a separate device-local ledger, never replayed from open/sync/import. Reduce Motion uses static levels and a brief completion badge. [Fixture CPU evidence and owner checks](docs/motion-verification.md); the final 60-second settled fixture run became occluded, so final energy and real MenuBarExtra acceptance remain pending.

**Real challenge activity now has its own production queue and sync coordinator.** The footer shows pending/synced/error state and clock/delivery warnings. Until the owner deploys the schema, existing history remains locally usable with sync errors; an empty device waits for a successful server check before setup. Diagnostic test-message sync remains independent.

### Implementation map

| Location | Role |
| --- | --- |
| `Sources/ChallengeCore/Challenge.swift` | UI/network-independent rules, deterministic event union/undo reconciliation, day summaries and derived streaks/milestones |
| `Sources/ChallengeCore/ChallengeStore.swift` | Account-scoped atomic history + pending queue, v1 backup/migration, exact acknowledgment; corrupt files throw rather than reset |
| `Sources/ChallengeCore/ChallengeSync.swift` | Immutable challenge settings/event wire records and injected transport seam |
| `Sources/DailyChallengeProof/SupabaseChallengeTransport.swift` | Authenticated insert-ignore batches, owner-scoped paginated reads; proof-style transport |
| `Sources/DailyChallengeProof/TrackerModel.swift` | Main-actor UI/sync coordinator, account generations, backoff, setup preflight and truthful status; one active writer |
| `Sources/DailyChallengeProof/TrackerView.swift` | Root navigation/setup, Today, water/habit controls; visible-window/midnight/wake refresh |
| `Sources/DailyChallengeProof/WaterJugView.swift`, `TrackerMotion.swift`, `CompletionEffect.swift`, `PopupVisibility.swift` | Finite motion schedules, local celebration ledger, noninteractive effects and native visibility gating |
| `Sources/DailyChallengeProof/HistoryTrackerView.swift` | Calendar, correction unlock, audit |
| `Sources/DailyChallengeProof/DailyChallengeProofApp.swift` | App entry, MenuBarExtra, retained account/diagnostics view |
| `Sources/DailyChallengeProof/ProofModel.swift` | Supabase password auth, Keychain sessions, proof queue/polling; not production challenge sync |
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

The build script embeds **public** configuration from `.env.local`; standalone `swift run` is not the supported configured launch path. The package uses Swift 6, macOS 14 minimum, and pinned `supabase-swift` 2.55.3.

## Product invariants

- All five daily requirements: **4,000 ml water, 45-minute workout (home/gym), 45-minute walk, clean diet, 10 Bible pages**. Non-water activities are self-certified; no rest-day exemptions or invented food rules.
- Every day is defined by **Europe/Jersey**, including DST, independently of device timezone. Earlier-than-start and future dates cannot be completed. Unrecorded closed tracked dates are missed.
- Incomplete or explicitly missed **today** preserves the consecutive complete run through yesterday until midnight. Add today when complete. Corrections recalculate current/best streaks and valid 75-day milestones from history.
- Each pour has a stable ID; undo references a specific pour, not a mutable total. Keep correction history. Local command retries require the original ID and edit timestamp.
- Local snapshot storage has one serialized writer per account/device. Production ordering is client timestamp → device ID → event ID; server receipt never reorders edits. A >5-minute receipt/client difference warns without dropping edits (offline delay also qualifies). Independent pours union; duplicate undos target one pour. Full immutable event history prevents resurrection.
- Shared start-date settings are immutable. Empty devices check the server/adopt before setup; offline new setup waits. Different challenge identities/settings stop sync and preserve both histories. There is no conflict-resolution UI in this increment.

## Backend and outstanding acceptance

Supabase replaced CloudKit because the Apple Developer membership is inactive and the Macs use different iCloud accounts. Both Macs will use the same app login. Public client configuration lives in `.env.local` (template `.env.example`); no admin key/password is needed by the app.

- Password login works on the first Mac. SMTP/OTP was abandoned after email delivery/template restrictions; retain the current password flow and existing Auth user. Passwords are not persisted; sessions use Keychain.
- Proof table `public.sync_probe_entries`: authenticated owner-only SELECT/INSERT, anonymous denied, client UPDATE/DELETE denied. Local RLS checks and a prior hosted anonymous-denial check passed; an actual uploaded test message was confirmed.
- Both Macs are **Apple Silicon, macOS 27.0.1 (26A434)**. Work policy permits the app. Home-Mac/two-Mac verification was explicitly deferred by the user, not passed.
- Keychain persistence after real relaunch, true offline recovery, all-interface/accessibility acceptance, and real two-Mac reconciliation remain manual/unproven.
- Builds are **ad-hoc signed, not Developer ID signed/notarized**. Preserve security controls. Paid memberships/subscriptions or deployment-policy bypasses require user approval. Keep credentials out of chat/docs; do not request service-role keys or delete Auth users to work around login issues.

## Roadmap and remaining acceptance

Work in separate verifiable increments; do not treat fixture success as owner/device acceptance:

1. **Production challenge sync — implementation complete, acceptance pending:** owner-protected migration, real activity/start-date sync, durable offline queue, idempotent retries, deterministic conflicts/undo, and pending/synced/error state. Version 1 is backed up before migration. Owner-hosted deployment and both actual Macs still need the [checklist](docs/production-sync.md#two-actual-macs-owner-acceptance-checklist).
2. **Settings/reminders/backups:** water reminder and opt-in launch-at-login implementations complete, native reminder delivery and owner checks pending (see above); validated JSON export/import with recovery backup implemented (native panel acceptance pending).
3. **Animation implementation complete; energy/owner acceptance pending:** bounded pour/slosh/undo/spill, non-replaying local daily/75-day celebrations and live Reduce Motion fallback. Fixture CPU measurements are recorded, but final settled-idle comparison is incomplete because the fixture became occluded. See [motion verification](docs/motion-verification.md) for exact numbers, remaining energy validation, and real-popup/VoiceOver/contrast/two-Mac checks. Optional dated diet-rule text is still deferred.

For UI/storage details, read [tracker interface](docs/tracker-interface.md) and [local foundation](docs/local-foundation.md). Before sync work, read [sync/storage plan](plans/sync-and-storage.md) and [Supabase instructions](supabase/README.md). Before reminder or distribution work, read the corresponding documents under [the overall plan](PLAN.md). These describe intended scope; this handoff records the latest user report and immediate priority.

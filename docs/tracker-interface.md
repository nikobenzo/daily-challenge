# Functional Tracker Interface (0.2)

## What is built

The user approved connecting the local foundation to the native menu-bar popup.

- Authenticated account → server adoption or explicit Jersey start-date setup; see [setup behavior](../README.md#first-mac-tracker-checks). All five requirements are explained.
- Today → drawn 4 L jug, actual uncapped ml count, +450 ml, latest-pour undo, and validated custom amounts.
- Workout (45 minutes, home/gym), walk (45 minutes), Bible (10 pages) → one-tap reversible marks.
- Diet → pending/clean/missed cycle; right-click for direct selection. No invented food rules.
- Current streak / 75, best streak, and number of currently valid milestones. Tracking does not stop at 75.
- History → Monday-first monthly calendar, distinct day-state symbols, explicit Edit this day unlock, selected-day water/habit corrections, and newest-first activity/correction audit.
- Account → the preexisting sign-in/session and separate test-message sync diagnostics, plus [personal-data backups](../README.md#personal-data-backups).
- Production challenge footer and manual retry; see [sync scheduling and status](production-sync.md#scheduling-and-status).

No Dock icon or ordinary main window. Supported system materials are used as the macOS 14+ fallback. See [motion usage](../README.md#current-state-functional-tracker-with-production-sync) and the [bounded motion implementation](motion-verification.md#implementation) for jug effects, celebrations and accessibility fallback. The calendar is a fixed-height native scroll surface: scroll to reach all marks and the audit.

## State and safety

`TrackerModel` owns exactly one `ChallengeStore` for the current app account. Real activity is never added to `ProbeJournal` or the proof table. Signing out clears the visible account state but preserves its file; switching accounts loads only the new account's file.

Each UI action refreshes the clock before choosing its target day. Today follows Jersey midnight. History selection stays fixed across midnight/wake, including when an edit is in progress; changing the selected date or returning to Today exits correction mode. Start-date setup never replaces an existing challenge.

Writes adopt the next UI state only after successful persistence. Save errors retain the previous amount/marks and show a message. Corrupt local history presents recovery/error UI, not setup or a reset. A fresh open, wake notification, visible-window refresh, and midnight refresh keep date/streak output current.

Data: `~/Library/Application Support/DailyChallenge/ujyvvyrugenknhjodfhc/challenge-<owner-uuid>.json`.

## Build and try

```bash
bash scripts/build-proof.sh
open "build/Daily Challenge.app"
```

Quit the older proof first. The legacy script/target name and `app.daily-challenge.proof` bundle ID remain intentionally unchanged for authentication continuity. The new bundle is named Daily Challenge and locally ad-hoc signed, not notarized. The old proof bundle is not overwritten by the build.

Follow the [first-Mac tracker checks](../README.md#first-mac-tracker-checks) before everyday tracking. Use History only for explicit corrections. The start date cannot be changed by rerunning setup. Do not delete or overwrite the account file to change it.

## Appearance

See [appearance selection](../README.md#current-state-functional-tracker-with-production-sync) for usage and [appearance verification](appearance-verification.md) for implementation details, fixtures, regression coverage and pending real-popup acceptance.

## Automated checks

```bash
swift test
bash scripts/test-sync-security.sh
```

Interface tests cover appearance preference persistence/mapping and production-root backing/live inheritance, plus complete-day setup/relaunch, custom pours/undo/validation, correction locking and targeting, Jersey midnight, account switching/sign-out, failed saves, corrupt-file preservation, future-date/duplicate-setup rejection, and offscreen native layouts at popup width. Render fixtures use isolated temporary account data, not your actual challenge or credentials. Native views are captured from never-shown test windows; no screen-recording permission is needed.

To inspect the older Today/History layout fixtures (not the appearance regression):

```bash
DAILY_CHALLENGE_SNAPSHOT_DIR=/tmp/daily-challenge-interface-previews \
  swift test --filter nativeTrackerSurfaces
```

## Manual acceptance still required

- Real sign-in/restoration with the rebuilt ad-hoc bundle and existing Keychain session.
- Menu-bar positioning/height at your screen scaling; custom-pour popover interaction and scrolling.
- Keyboard-only navigation and VoiceOver; system contrast, transparency and Reduce Motion settings.
- Quit/relaunch with real local records; wake/overnight transitions.
- Both-Mac install and diagnostics convergence; see the separate [production acceptance checklist](production-sync.md#two-actual-macs-owner-acceptance-checklist).
- [Motion energy evidence and outstanding owner checks](motion-verification.md#fixture-cpu-measurements--acceptance-remains-incomplete).

See [Account settings usage](../README.md#current-state-functional-tracker-with-production-sync) and the [current roadmap](../HANDOFF.md#roadmap-and-remaining-acceptance) for implemented settings, deferred features and feature-specific owner acceptance.

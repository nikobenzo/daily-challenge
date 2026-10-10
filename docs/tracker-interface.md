# Functional Tracker Interface (0.2)

## What is built

The user approved connecting the local foundation to the native menu-bar popup.

- Authenticated account → server adoption or explicit start-date and timezone setup (searchable picker defaulting to this Mac's zone; never shown when adopting); see [setup behavior](../README.md#first-mac-tracker-checks). All five requirements are explained.
- Today → five ring gauges (water %, workout, walk, diet, Bible), drawn 4 L jug, actual uncapped ml count, +450 ml, latest-pour undo, and validated custom amounts.
- Workout (45 minutes, home/gym), walk (45 minutes), Bible (10 pages) → one-tap reversible marks on their Today rings and History pills.
- Diet → pending/clean/missed cycle; right-click for direct selection. No invented food rules.
- Current streak / 75, best streak, and number of currently valid milestones. Tracking does not stop at 75.
- History → Monday-first monthly calendar, distinct day-state symbols, explicit Edit this day unlock (pencil), selected-day water/habit corrections, and newest-first activity/correction audit.
- Account → the preexisting sign-in/session and separate test-message sync diagnostics, plus [personal-data backups](../README.md#personal-data-backups) and the Extras row (below).
- Extras → optional personal daily to-dos under the rings; [daily checklist extras](#daily-checklist-extras).
- Production challenge footer and manual retry; see [sync scheduling and status](production-sync.md#scheduling-and-status).

No Dock icon or ordinary main window. The popup follows the [design system](design-system.md): a glass sheet and detached footer. See [motion usage](../README.md#current-state-functional-tracker-with-production-sync) and the [bounded motion implementation](motion-verification.md#implementation) for jug effects, celebrations and accessibility fallback. History and Account share one fixed height; the History Activity list scrolls inside it.

## Daily checklist extras

Personal daily to-dos beside the five requirements (roadmap phase 7, captain decision D7): **extras never count toward a complete day or the 75-day streak.** `DailySummary.isComplete`, streaks and milestones ignore them; `extrasDone`/`extrasTotal` are for display only.

- **Today:** a collapsible **Extras** section under the rings (`ExtrasViews.swift`): checklist icon, `done/total` badge (green with a check when all are done), a chevron, and the **Manage extras** button (`square.and.pencil`). One round checkbox per extra: an empty ring, or a green disc with a check. Collapsing and expanding resizes the glass through the normal animated popup height. **With no extras** the same place holds one slim collapsed row, checklist icon, **Extras**, the hint "Add your own to-dos" and a chevron (a button labelled "Add extras"); clicking it drops the Manage extras caption and add field down inline under the header (ease-in-out 0.28 s, the chevron rotates, the glass grows through the same animated height; Reduce Motion cross-fades), and clicking again collapses it. Adding the first extra cross-fades the editor into the checklist; archiving the last one returns the collapsed row. The Account row and the pencil are unchanged. Ticking the last open extra today shows "All extras done!" once through the existing non-replaying celebration ledger (its own `extras` key per day); opening, syncing, importing, or undo and re-tick never replay it, and it never fires for a past day.
- **History:** a fifth pill beside the habit pills (`checklist` + `done/total`) opens that day's checklist. Ticks follow the habit rules: today directly, a past day only after **Edit this day**. The Activity audit lists added, renamed and archived extras and each tick.
- **Manage extras** (popover from the Today section header and from **Account → Extras**; the first extra can also be added from Today's empty row): add, rename, archive. At most **10 active**; at the cap the add field is replaced by "Up to 10 extras. Archive one to add another." Names are trimmed, 1 to 40 characters, one line. Archive asks for confirmation because it is permanent. No reordering, reminders, notes or per-item icons in this version.
- **Which extras a day shows:** every defined extra (a definition's own day is ignored, so a new extra also appears on earlier days, unticked) except those archived on or before that day. Archiving hides an extra from its archive day on; earlier days keep it and their ticks.

**Model and wire format** (`Challenge.swift`). Three owner-scoped `Action` cases travel through the existing event log, transport and server table: `defineExtra(id:title:)` adds or renames (the last definition in event order wins), `archiveExtra(id:)` archives permanently, `setExtra(id:completed:)` ticks for the event's day. Their JSON is the synthesized form documented on `Challenge.Action` (`{"defineExtra":{"id":…,"title":…}}`, `{"archiveExtra":{"id":…}}`, `{"setExtra":{"id":…,"completed":…}}`) and must never be renamed. Definitions and archives are recorded on today whichever day is selected, without the correction lock.

**Validation.** Recording (this Mac's edits) refuses an invalid name, an 11th active extra, renaming an archived extra, and ticking an undefined extra or one archived on or before the tick's day. `merge` (sync, snapshots, imports) rejects only what can never be valid on any device: an invalid name, or an archive or tick for an extra **never defined anywhere in the union**. It deliberately does not reject a tick on an archived extra or a tick ordered before its definition: a Mac offline when another archived the extra, or with a slower clock, produces exactly that, and rejecting it would stop sync for both Macs (firstmate decision, 9 October 2026). Archives are order-independent: the earliest archive day wins and nothing unarchives. Two Macs adding extras offline can exceed 10 active after sync; the list shows them all and adding waits until enough are archived.

**Server.** The abuse-limit check that allowed only the original four action kinds is widened by the owner-applied `supabase/migrations/20261010000100_extras_action_kinds.sql` ([owner step](production-sync.md#extras-update-owner-only-once)); no transport or other schema change.

## State and safety

`TrackerModel` owns exactly one `ChallengeStore` for the current app account. Real activity is never added to `ProbeJournal` or the proof table. Signing out clears the visible account state but preserves its file; switching accounts loads only the new account's file.

Each UI action refreshes the clock before choosing its target day. Today follows midnight in the challenge's timezone. History selection stays fixed across midnight/wake, including when an edit is in progress; changing the selected date or returning to Today exits correction mode. Start-date setup never replaces an existing challenge.

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

Interface tests cover appearance preference persistence/mapping and production-root backing/live inheritance, the Extras section (the empty-state row collapsed and with its add field dropped down on the production root, the first extra turning it into the checklist and the last archive returning it, the collapsible checklist, Light and Dark renders of Today, History's extras pill and Manage extras empty/in use/at the cap: `extrasSectionHasAdaptiveGlassInBothAppearances`, plus `ExtrasTests`), plus complete-day setup/relaunch, custom pours/undo/validation, correction locking and targeting, Jersey and Sydney midnight, zone-specific setup and reminders, account switching/sign-out, failed saves, corrupt-file preservation, future-date/duplicate-setup rejection, and offscreen native layouts at popup width. Render fixtures use isolated temporary account data, not your actual challenge or credentials. Native views are captured from never-shown test windows; no screen-recording permission is needed.

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

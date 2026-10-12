# Functional Tracker Interface (0.2)

## What is built

The user approved connecting the local foundation to the native menu-bar popup.

- Authenticated account → server adoption or explicit start-date and timezone setup (searchable picker defaulting to this Mac's zone; never shown when adopting); see [setup behavior](DEVELOPMENT.md#first-mac-tracker-checks). All five requirements are explained.
- Today → five ring gauges named for the day's targets (water %, workout, walk, diet, Bible by default), a drawn jug that is full at the day's water goal, actual uncapped ml count, + the day's glass (450 ml by default), latest-pour undo, and validated custom amounts; see [custom daily goals on the Mac](#custom-daily-goals-and-repeating-extras-on-the-mac).
- Two activities and reading (Workout 45 minutes home or gym, Walk 45 minutes, Bible 10 pages unless changed) → one-tap reversible marks on their Today rings and History pills.
- Diet → pending/clean/missed cycle; right-click for direct selection. No invented food rules.
- Current streak / 75, best streak, and number of currently valid milestones. Tracking does not stop at 75.
- History → Monday-first monthly calendar, distinct day-state symbols, explicit Edit this day unlock (pencil), selected-day water/habit corrections, and newest-first activity/correction audit.
- Account → the preexisting sign-in/session and separate test-message sync diagnostics, plus [personal-data backups](DEVELOPMENT.md#personal-data-backups) and the Extras row (below).
- Extras → optional personal to-dos under the rings that carry over until done, or repeat on chosen days; [daily checklist extras](#daily-checklist-extras).
- Production challenge footer and manual retry; see [sync scheduling and status](production-sync.md#scheduling-and-status).

No Dock icon or ordinary main window. The popup follows the [design system](design-system.md): a glass sheet and detached footer. See [motion usage](DEVELOPMENT.md#current-state-functional-tracker-with-production-sync) and the [bounded motion implementation](motion-verification.md#implementation) for jug effects, celebrations and accessibility fallback. History and Account share one fixed height; the History Activity list scrolls inside it.

## First launch

A launch opens no window of its own except, on a Mac that still needs setup, the welcome window. The popup only opens from the menu-bar drop (or from the welcome window's button).

**The empty "Daily Challenge Settings" window (fixed 12 October 2026).** From the switch to the app's own status item and panel (ec8f705, 9 October) until this fix, every launch showed an empty 900 × 450 window titled "Daily Challenge Settings". Diagnosis on macOS 27.0.1 with an isolated copy (its own bundle ID, no configuration, no saved state):

- **Trigger:** the app was a SwiftUI `App` whose only scene was `Settings { EmptyView() }`, kept because a SwiftUI `App` must declare a scene. SwiftUI presents that scene's window at launch when it is the app's only scene.
- **Not the cause:** `open` versus running the binary directly (both showed it), an already-running instance (the installer quits it first; a fresh launch reproduced it) and window restoration (no saved state existed; the captain's own running copy had the window, closed, with its frame stored under `NSWindow Frame com_apple_SwiftUI_Settings_window`).
- **Why it went unnoticed:** the real-popup probe captures only the popup window, renders never launch the app, and the window can open on another display or behind other windows.
- **Fix:** the app no longer uses the SwiftUI `App` lifecycle. `main.swift` starts `NSApplication` with `AppDelegate`, so no scene exists that could open a window. `AppMenu` supplies the never-shown main menu whose key equivalents give text fields Cut, Copy, Paste, Select All and Undo (SwiftUI's default menu used to), Command-W and Command-Q. Opening the app again while it runs brings the welcome window forward, or else opens the popup.

**Welcome window** (`WelcomeWindow.swift`, `WelcomeView.swift`, `FirstRun.swift`, `Confetti.swift`; styling in [design system](design-system.md#welcome-window)). A menu-bar sketch with the real drop glyph and a "Daily Challenge lives here" callout, then four steps with the current one highlighted: find the drop in the menu bar (ticked once the popup has opened), create an account or sign in, choose your daily five and a start date, log the day (the standard five "unless you choose your own", with each goal's icon; once the challenge starts, the goals chosen in setup). Its button leads into the popup: **Create an account** (or the **I already have an account** link) opens the popup at that auth screen; once signed in, **Choose your start date** opens setup. It follows the real auth and tracker state, so signing in or starting from the popup directly ticks the steps too. When the challenge starts (or is adopted from the server) while it is up, it shows "You're all set" and names the goals in force on day 1 ("Day 1 is Mon 12 Oct. Click the drop in the menu bar each day to log 3,000 ml of water, Gym 45 min, ...") with one confetti burst, then closes itself after 8 seconds (or **Done**). The window sits under the menu bar, left of where the popup opens, so the two never overlap. Escape, Command-W and the close button dismiss it for this launch.

**When it shows** (`FirstRunState.decision`, unit-tested in `FirstRunTests`):

| This Mac | Result |
| --- | --- |
| `firstRunFinished` stored in this Mac's defaults | never |
| Any `challenge-*.json` in the challenge folder (upgraded install or an existing user, signed in or not) | never, and `firstRunFinished` is stored |
| Saved session not read yet | waits, so a returning person is never shown it while the Keychain session restores (`AuthModel.sessionRestored`) |
| Signed in with a challenge | never, and stored |
| Signed in, no challenge | the start-date step |
| Signed out | the menu-bar step, then the account step once the popup has opened |

Dismissing it does not store anything: it returns at the next launch until setup is done. The decision is device-local and never synced. New steps (for example future customizable requirements) are new `WelcomeStep` cases with their title, detail and decision rule; the view lists `allCases` in order.

**Motion.** The icon pulses three times when the window appears; the confetti is one seeded 3.2 s burst that ends by itself, starts only while the window is on screen, and is replaced by the static check under Reduce Motion. Nothing animates afterwards.

**Regression check and evidence.** `bash scripts/test-first-launch.sh` (after `scripts/build-proof.sh --adhoc`) opens an isolated copy with `open`, as `site/install.sh` does, and fails on any Settings window, any empty 900 × 450 window or any window other than the expected one. It then runs the probe's welcome screens on offline fixtures in Light and Dark: new person and signed in without a challenge show only the welcome window; existing user and upgraded install show none; starting the challenge opens the popup from the welcome button, celebrates, stores that setup is done and closes the window by itself. Reverting to the `Settings` scene fails every one of these checks. `--docs` refreshes [`screenshots/onboarding/`](screenshots/onboarding/): WindowServer captures of the real welcome window (`welcome-*`, `welcome-signed-in-*`, `welcome-done-*-celebration` mid-confetti, `-settled` after it, and a Reduce Motion celebration) with each launch's window report (`.json`). The copy reads only the file names in the real challenge folder, to tell whether this Mac has an existing user; on the owner's Mac it therefore expects no window at all.

Captain checks a capture cannot make: the first launch from the real installer on a Mac with no challenge (a second user account works), VoiceOver reading the steps, Return and Escape in the window, and the window's placement with the menu bar on another display.

## Daily checklist extras

Personal to-dos beside the five requirements (roadmap phase 7, captain decision D7): **extras never count toward a complete day or the 75-day streak.** `DailySummary.isComplete`, streaks and milestones ignore them; `extrasDone`/`extrasTotal` are for display only. Since 11 October (captain) an extra is a to-do that **carries over until it is done**: ticked, it leaves the following days; left open, it reappears on each new day marked **Late** ([day rules](#which-days-an-extra-shows)). D7's first version showed every extra on every day.

- **Today:** a collapsible **Extras** section under the rings (`ExtrasViews.swift`): checklist icon, `done/total` badge (green with a check when all are done), a chevron, and the **Manage extras** button (`square.and.pencil`). One round checkbox per extra: an empty ring, or a green disc with a check; a carried-over extra has a small amber **Late** caption after its title (`LateMarker`, `Theme.amberText` in the caption font, never a pill; the help tag and VoiceOver say "<title>, late"). Collapsing and expanding resizes the glass through the normal animated popup height. **With no extras** the same place holds one slim collapsed row, checklist icon, **Extras**, the hint "Add your own to-dos" and a chevron (a button labelled "Add extras"); clicking it drops the Manage extras caption and add field down inline under the header (ease-in-out 0.28 s, the chevron rotates, the glass grows through the same animated height; Reduce Motion cross-fades), and clicking again collapses it. Adding the first extra cross-fades the editor into the checklist; archiving the last one returns the collapsed row. The Account row and the pencil are unchanged. Ticking the last open extra today shows "All extras done!" once through the existing non-replaying celebration ledger (its own `extras` key per day); opening, syncing, importing, or undo and re-tick never replay it, and it never fires for a past day.
- **History:** a fifth pill beside the habit pills (`checklist` + `done/total`) opens that day's checklist (`ExtrasDayPopover`), with the same Late captions. Ticks follow the habit rules: today directly, a past day only after **Edit this day**. The Activity audit lists added, renamed and archived extras and each tick.
- **Manage extras** (popover from the Today section header and from **Account → Extras**; the first extra can also be added from Today's empty row): add, rename, archive the **open** extras (`TrackerModel.activeExtras`, `Challenge.openExtras(asOf:)`). At most **10 open**; at the cap the add field is replaced by "Up to 10 extras. Archive one to add another." Names are trimmed, 1 to 40 characters, one line. Archive asks for confirmation because it is permanent. No reordering, reminders, notes or per-item icons in this version.

### Which days an extra shows

These are the rules for one-off extras, every extra's rule until it is scheduled; [recurring extras](#custom-daily-targets-and-recurring-extras-shared-rules) follow their own. All of it is derived from the existing `defineExtra`, `archiveExtra` and `setExtra` events (`Challenge.allExtras`), the same on the Mac, the iPhone and its widgets: no new action kind, no stored state, no server change, and nothing is written at midnight.

- **First day** (`Extra.firstDay`): the day of its earliest definition, which is the day it was added (definitions are recorded on today in the challenge zone, whichever day is selected). A new extra never appears on earlier days.
- **Completion day** (`Extra.completedOn`): the earliest day whose last tick, in event order, is ticked. Ticks from the archive day on never count.
- **Shown** on its first day and every following day while open, through its completion day, and never from its archive day on. It is ticked only on its completion day.
- **Late** (`DailySummary.isLate`) on every day after its first day, ticked or not, so a day it was finished late keeps the caption.
- **Past-day corrections** (Edit this day): unticking the completion day reopens it, so it carries over again to today; ticking an earlier carried-over day moves the completion there and removes it from the following days.
- **Rename** changes the title wherever it shows, never its days. **Archive** hides it from the archive day on; earlier days keep it with their ticks.
- **Rollover:** days are calendar days in the challenge timezone, so at the challenge zone's midnight an open extra appears on the new day as late; the widgets' midnight timeline entries derive the same.
- **The cap** counts open extras: neither archived nor completed on or before today. Ticking one frees its place at once; it stays ticked on Today until midnight but leaves Manage extras. Unticking can leave more than 10 open, as can two devices adding offline; adding then waits.
- **Earlier histories** keep their stored events and render under these rules. An extra ticked on several days under the every-day rule counts as done on its earliest ticked day, which also becomes its first day when that is before its definition, and no longer shows afterwards; its later ticks stay in Activity. An extra never ticked is late from the day after it was added and no longer shows before it. A device still on an earlier build keeps showing every extra on every day from the same events until it updates.

**Model and wire format** (`Challenge.swift`). Three owner-scoped `Action` cases travel through the existing event log, transport and server table: `defineExtra(id:title:)` adds or renames (the last definition in event order wins), `archiveExtra(id:)` archives permanently, `setExtra(id:completed:)` ticks for the event's day. Their JSON is the synthesized form documented on `Challenge.Action` (`{"defineExtra":{"id":…,"title":…}}`, `{"archiveExtra":{"id":…}}`, `{"setExtra":{"id":…,"completed":…}}`) and must never be renamed. Definitions and archives are recorded on today whichever day is selected, without the correction lock.

**Validation.** Recording (this Mac's edits) refuses an invalid name, an 11th open extra, renaming an archived extra, and ticking an undefined extra or one archived on or before the tick's day. `merge` (sync, snapshots, imports) rejects only what can never be valid on any device: an invalid name, or an archive or tick for an extra **never defined anywhere in the union**. It deliberately does not reject a tick on an archived extra or a tick ordered before its definition: a Mac offline when another archived the extra, or with a slower clock, produces exactly that, and rejecting it would stop sync for both Macs (firstmate decision, 9 October 2026). Archives are order-independent: the earliest archive day wins and nothing unarchives. Two Macs adding extras offline can exceed 10 open after sync; the list shows them all and adding waits until enough are done or archived.

**Server.** The abuse-limit check that allowed only the original four action kinds is widened by the owner-applied `supabase/migrations/20261010000100_extras_action_kinds.sql` ([owner step](production-sync.md#extras-update-owner-only-once)); no transport or other schema change.

## Custom daily targets and recurring extras (shared rules)

Phases P1a and P1b of the custom goals plan (captain's decisions of 12 October): the rules, wire format and server checks for choosing your own daily targets and for extras that repeat, in `ChallengeCore` and the Android core alike. **Almost no screen uses them yet:** setup rows, editors, captions, labels and public text are later phases (P2 shows targets, P4 edits them, P5 adds the repeat picker), and a challenge without the new events behaves exactly as before. The exception is the iPhone and Android **water widgets**: + pours the tap day's glass size, read from the stored targets inside the lock (never from what the widget drew), and the jug, totals, Lock Screen ring and spoken value follow that day's goal; with the standard targets they are unchanged. Their gallery descriptions and the iPhone intent title still say 450 ml and 4,000 ml (public text, P6). The Mac shows, edits and repeats them (P2, P4 and P5 on the Mac; see [below](#custom-daily-goals-and-repeating-extras-on-the-mac)).

**Targets** (`Challenge.Targets`, `DailySummary.targets`). There are always five slots: water plus `workout`, `walk`, `diet` and `bibleReading`. The slot keys only identify a ring and its `setHabit`/`setDiet` events, so the `walk` slot may be called Yoga and is still ticked with `setHabit("walk")`. Water has a daily goal (1,000 to 5,000 ml) and a glass size (50 to 1,000 ml, no more than the goal). Each other slot has a name (trimmed, 1 to 20 characters on one line, at most 80 Unicode scalars), an optional amount with its unit (minutes 5 to 300, pages 1 to 500, chapters 1 to 50, kilometres 1 to 100, miles 1 to 60, steps 1,000 to 50,000; diet takes none) and an optional icon id (1 to 16 lower-case letters; an id this version does not know shows the slot's default). Amounts are display only: completion is still the tick, or a clean day. The standard targets (`Targets.standard`) are 4,000 ml in 450 ml glasses, Workout 45 minutes, Walk 45 minutes, Diet, and Bible 10 pages.

**Which targets a day uses** (`Challenge.targets(on:)`). Start from the standard five and apply every `setTarget` and `setWater` dated that day or earlier; per slot, the latest dated change wins, then the last in event order (client time, device ID, event ID). So two devices changing one slot on one day resolve like conflicting habit edits, changes to different slots both survive, and a change never re-judges the days before it. `waterComplete` and a complete day compare against **that day's** goal: lowering today's goal below today's total completes water at once, raising it can un-complete today, a correction on a past day is judged by that day's goal, and streaks and milestones are recomputed across changes as before. `record` refuses an invalid target (`invalidTarget`); `merge` applies the same day-range checks as other events and does not require today (only the UI will limit changes to today).

**Setup with targets.** `ChallengeStore.start(on:timeZone:targets:at:)` (and `TrackerModel.startChallenge(on:timeZone:targets:)`; Android `ChallengeStore.start` and `Tracker.startChallenge`) records one event per value that differs from the standard five, dated the start day, in the same atomic commit as the settings. The standard targets write nothing. An invalid target, or a start after `at`, refuses the whole setup and writes no file.

**Recurring extras** (`Challenge.ExtraSchedule`, `Extra.schedule`). An extra is still defined, renamed and archived with `defineExtra`/`archiveExtra` and ticked per day with `setExtra`; `scheduleExtra(id:weekdays:every:)` sets how it repeats **from the event's day**: chosen ISO weekdays (Monday = 1), every N days (1 to 30, 1 is daily) counted from the day the rule applies from, or neither for a one-off to-do. A rule dated before the definition day applies from the definition day; on one day the latest dated rule wins, then the last in event order.

- On a day with a repeating rule it shows when the rule matches (weekdays and day counts use calendar dates in the challenge zone, so daylight-saving changes never shift them), is ticked if that day's last tick is ticked, is **never late** and never carries over. Unscheduled days do not show it.
- Days before a change keep their earlier display: a to-do made recurring from today still shows on its first day as before.
- Recurring back to a to-do starts a **fresh open to-do** from that day: only a tick inside that period completes it, and it carries over as late from the day after. A to-do rule right after a to-do period changes nothing, so a finished to-do stays finished.
- **The cap of 10** counts open to-dos plus active recurring extras (`openExtras(asOf:)`). Scheduling a finished to-do makes it open again, so at the cap it is refused with `tooManyExtras`. `record` also refuses an invalid rule (`invalidSchedule`), an unknown extra and an archived one, and records nothing when the rule in force that day is already the same. `merge` rejects a schedule only for an extra never defined anywhere in the union.
- `done/total`, `allExtrasDone` and `completedExtras` include the day's recurring items; extras still never count toward a complete day.

**Wire format and old clients.** The new kinds are synthesized `Codable` like the others (documented on `Challenge.Action` and in Android `Wire.kt`), with absent values left out: `{"setTarget":{"_0":"walk","name":"Yoga","amount":30,"unit":"minutes","icon":"yoga"}}`, `{"setWater":{"goal":3000,"pour":250}}`, `{"scheduleExtra":{"id":"<UUID>","weekdays":[1,2,3,4,5]}}`. A target or schedule outside the rules is unreadable to the decoders, like an unknown kind: sync skips the row and files refuse it, so it never fails a merge. iPhone 1.0, Mac 1.0 and Android phase 1 skip all three kinds and keep syncing (proved with a frozen copy of the 1.0 decoder in `OldClientCompatibilityTests`): they judge water against 4,000 ml, show the standard labels, and show a recurring extra as a one-off that leaves after its first tick. A schedule is its own kind because a new definition kind would make their merge refuse the first tick (`unknownExtra`, stopping sync) and a key inside `defineExtra` would be dropped by their next rename. The skipped-rows note now ends "Updating Daily Challenge may show it" (or "them") on all three clients.

**Elsewhere.** Water reminders stop for a day once that day's own goal is met (`WaterReminderPlanner.upcoming(goal:)`, the controller's per-day goal and status). Exports are format version 4 when they may hold the new kinds; versions 1 to 3 still import. The local snapshot stays version 2. The Activity audit lists the new kinds (on the Mac: "Walk changed to Yoga · 30 min", "“Stretch” repeats every day").

**Tests.** The parity vectors (`test-vectors/generate.py`) cover the encodings, 56 refused payloads, names and icons, and rule cases for targets (defaults, setup on a past start day, change from today, same-slot and different-slot conflicts, later-dated wins, lowering and raising today's goal, streaks across changes, past corrections) and recurring extras (daily, weekdays across daylight saving in three zones, every N, schedule changes, archive, back to a to-do, multi-device merges, the cap, refusals). Swift and Kotlin both run them; Swift unit tests cover setup, decoding, backups v4 and reminders, and Android `TargetsTest` the same in the Kotlin core.

**Server.** `supabase/migrations/20261012000100_custom_targets_action_kinds.sql` widens the action-kind check and bounds the three payloads, never more strictly than the clients ([owner step](production-sync.md#custom-goals-update-owner-only-once)). Not applied to the hosted project.

## Custom daily goals and repeating extras on the Mac

Phases P2, P4 and P5 of the custom goals plan on the Mac, on the [shared rules](#custom-daily-targets-and-recurring-extras-shared-rules). Words, icons and presets: `Goals.swift`; editors: `GoalsViews.swift`; repeat picker: `ExtrasViews.swift`.

- **Every surface reads the selected day's targets** (`DailySummary.targets`). Today's ring labels, icons, tooltips and VoiceOver ("Yoga, 30 minutes"; diet "No sugar, your own rules"), the water ring and totals ("/ 3,000"), the jug (full at that day's goal, droplets and spill above it; `WaterJugView(goal:)`, `WaterMotion(goal:)`) and the + button ("+ 330 ml"; `TrackerModel.addWater()` pours the selected day's glass, read from the just-loaded summary). History's pills, the Activity audit's tick names ("Yoga complete") and its day card use that day's targets, so a day before a change keeps its own. A long name (up to 20 characters) scales down, then truncates in its ring; the tooltip and VoiceOver read it in full. The water reminder no longer names a number, because notifications are queued ahead and the goal can change: "Time for some water. Drink only what you still need toward today's goal."
- **Setup** replaces the five fixed rings with **Your daily five**: five rows (water, the two activities, diet, reading) showing the target in force, each opening its editor in a popover anchored to the row, then "Change any of these now, or later in Account." Start date, time zone and **Start challenge** are unchanged, so accepting the standard five is still one click and writes nothing new; chosen targets are recorded on the start day in the same commit (`startChallenge(on:timeZone:targets:)`). The rules popover adds that goals can change later and earlier days keep theirs.
- **Editors.** Water: daily goal stepper (1,000 to 5,000 ml in 250 ml steps), glass presets 250, 330, 450, 500, 750 or **Other…** (50 to 1,000 ml, not more than the goal), "The + button adds 330 ml. About 10 glasses a day." Activities and reading: the plan's presets as capsules (Workout, Gym, Run, Cycle, Swim, Yoga, Pilates, HIIT; Walk, Yoga, Pilates, Stretching, Run, Cycle, Steps; Bible, Book, Audiobook, Devotional, Study) and **Custom…** with an icon picker, the name (1 to 20 characters, one line), an optional amount with its unit (minutes 5 to 300, pages 1 to 500, chapters 1 to 50, km 1 to 100, miles 1 to 60, steps 1,000 to 50,000; typed or stepped; or "No amount"), a "Shows as" preview and "You tick it yourself when it's done." Diet: its presets (Diet, Clean eating, No sugar, No alcohol) and a name only. Every limit shows its message under the editor ("Use 20 characters or fewer (24 now).", "A glass can't be more than the daily goal.") and disables **Done**. Choosing a slot's first preset is exactly the standard target and records nothing.
- **Account › Daily goals** expands in place to the same five rows. Each editor's **Done** records the changed values on **today** in the challenge's zone, in one commit (`TrackerModel.setTargets`, `ChallengeStore.record(all:on:at:)`): "Changes apply from today, Mon 12 Oct. Earlier days keep the goals they had." Saving unchanged goals records nothing; a failed save keeps everything as it was.
- **Activity audit:** "Walk changed to Yoga · 30 min", "Yoga changed to 20 min" (same name), "Water goal changed to 3,000 ml", "Glass changed to 330 ml", "Water now 3,000 ml · 330 ml glass" (both; the tooltip and VoiceOver read "Daily goal: Water goal changed to 3,000 ml, 330 ml glass, from this day on"), "“Stretch” repeats every day", "“Book the dentist” is a to-do again".
- **Repeating extras.** Manage extras rows show each open extra's rule ("Once", "Every day", "Weekdays", "Mondays", "Mon, Wed, Fri", "Every 3 days"); the pencil opens the name and **Repeat** panel: Once, Every day, Weekdays, Choose days (M T W T F S S toggles, at least one) or Every N days (2 to 30, counted from today), saved from today (`TrackerModel.scheduleExtra`). Today's and History's checklists caption a repeating extra in the ordinary tertiary caption ("every day", "weekdays", "Mondays"; only Late is amber), VoiceOver reads "Stretch, every day", and it is never Late. The caption under Manage extras reads "Your own to-dos: once, carried over until done, or repeating on days you choose."
- **A server without the custom goals update.** An upload holding a target or schedule refused by the v2 action-kind check (`23514`) becomes `ChallengeSyncError.serverNeedsCustomGoalsUpdate`: the footer shows "Sync unavailable · … · The server needs the update for custom goals and repeating extras before these changes can sync (see docs/production-sync.md). Nothing is lost: they stay saved here and upload once it is applied.", Account › Daily goals adds an amber note, and the whole batch stays pending until the [owner step](production-sync.md#custom-goals-update-owner-only-once); then it uploads. Tested on the fake transport (`serverWithoutTheGoalsUpdateRefusesGoalChangesClearlyAndKeepsThemPending`).
- **Tests and evidence:** `DailyGoalsTests` (interface: renders of setup, editors, Account, Today, History, Manage extras and the repeat panel in Light and Dark, words, presets, limits, welcome text), `DailyGoalsModelTests` (model and store) and the transport test above; captures in [Mac custom goals evidence](mac-custom-goals-evidence.md). The real-popup probe's `today-goals` screen seeds custom goals and repeating extras.

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

Follow the [first-Mac tracker checks](DEVELOPMENT.md#first-mac-tracker-checks) before everyday tracking. Use History only for explicit corrections. The start date cannot be changed by rerunning setup. Do not delete or overwrite the account file to change it.

## Appearance

See [appearance selection](DEVELOPMENT.md#current-state-functional-tracker-with-production-sync) for usage and [appearance verification](appearance-verification.md) for implementation details, fixtures, regression coverage and pending real-popup acceptance.

## Automated checks

```bash
swift test
bash scripts/test-sync-security.sh
```

Interface tests cover appearance preference persistence/mapping and production-root backing/live inheritance, the Extras section (the empty-state row collapsed and with its add field dropped down on the production root, the first extra turning it into the checklist and the last archive returning it, the collapsible checklist, Light and Dark renders of Today, History's extras pill and Manage extras empty/in use/at the cap: `extrasSectionHasAdaptiveGlassInBothAppearances`; carried-over Late extras on Today and in History's day popover, and a completed extra gone the next day: `carriedOverExtrasShowLateAndCompletedOnesLeaveLaterDays`, plus `ExtrasTests` and the day-rule tests in `ChallengeExtrasTests`), plus complete-day setup/relaunch, custom pours/undo/validation, correction locking and targeting, Jersey and Sydney midnight, zone-specific setup and reminders, account switching/sign-out, failed saves, corrupt-file preservation, future-date/duplicate-setup rejection, and offscreen native layouts at popup width. Render fixtures use isolated temporary account data, not your actual challenge or credentials. Native views are captured from never-shown test windows; no screen-recording permission is needed.

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

See [Account settings usage](DEVELOPMENT.md#current-state-functional-tracker-with-production-sync) and the [current roadmap](../HANDOFF.md#roadmap-and-remaining-acceptance) for implemented settings, deferred features and feature-specific owner acceptance.

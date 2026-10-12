# Mac custom goals evidence (12 October 2026)

Phases P2 (show each day's targets), P4 (setup rows and editors, Account › Daily goals, Activity
audit, the unmigrated-server message) and P5 (repeat picker, captions, repeating extras on Today and
History) on the Mac. [Behaviour](tracker-interface.md#custom-daily-goals-and-repeating-extras-on-the-mac).
Worker verification only, on macOS 27.0.1 (26A434): offline fixtures, a fake transport and isolated
probe copies of an ad-hoc build. No real account, Keychain, upload, server change or installed app was
touched, and the custom goals migration was not applied.

## Fixtures

- **Interface tests** (`Tests/TrackerInterfaceTests/DailyGoalsTests.swift`): a temporary account on
  Monday 12 October 2026 in Europe/London. The custom set is Gym 45 min, Yoga 30 min, No sugar,
  Audiobook 20 min, and 3,000 ml in 330 ml glasses.
- **Real-popup probe** `today-goals` (`PopupProbe.seedGoals`): Day 3, Thursday 8 October, in Jersey.
  The same custom set applies from today. "Book the dentist" was added on day 1 and is still open,
  so it is Late. Three repeating extras: Stretch every day (ticked), Pack lunch on weekdays, and
  Call Mum on Thursdays. Yoga is ticked and 900 ml is poured.

## Tests

- `swift test`: **242 tests passed**. New tests:
  - `DailyGoalsTests` (14): renders of every surface in Light and Dark; words, presets, limits and
    their messages; setup with the standard and custom five; unchanged goals record nothing; changes
    apply from today; audit wording; welcome text, with no dashes; long names in the ring row; repeat
    captions and picker mapping; repeating extras never Late.
  - `DailyGoalsModelTests` (6): goals recorded on today whichever day is selected; + pours the
    selected day's glass; a failed save writes none of the changes; invalid goals and rules are
    refused with their messages; repeat rules from today; `record(all:)` commits all or nothing.
  - `serverWithoutTheGoalsUpdateRefusesGoalChangesClearlyAndKeepsThemPending`: on the fake
    transport, the server refuses the upload with `23514` on the v2 check. The clear message shows,
    the pour and the goal stay pending together, and both upload once the server accepts them.
- One full run had a single failure in `PopupResizeTests.panelGrowsBeforeAndShrinksAfterTheAnimatedSheet`
  (panel height after the animated resize). Three runs of that suite on its own and the full rerun
  all passed, so I read it as timing under load, not a regression.
- iPhone app with the shared changes (a disposable iPhone 17 / iOS 27.0 simulator):
  - `** TEST BUILD SUCCEEDED **`.
  - `DailyChallengeTests`: 42 Swift Testing tests and 6 widget render tests passed.
  - UI tests were not run.

## Screenshots

| Evidence | Kind | Files |
| --- | --- | --- |
| Setup with Your daily five | **real popup** (`"capture": "window-server"`) | `screenshots/real-popup/setup-{light,dark}.png` |
| Today with custom goals and repeating extras | **real popup** | `screenshots/real-popup/today-goals-{light,dark}.png` |
| Account with the Daily goals row | **real popup** | `screenshots/real-popup/account-{light,dark}.png` |
| Welcome steps ("Choose your daily five and a start date") and celebration naming the goals | **real welcome window** (`scripts/test-first-launch.sh`, passed) | `screenshots/onboarding/welcome-*.png` |
| Setup, standard and custom | in-process render | `screenshots/appearance-fixtures/goals-setup{,-custom}-*.png` |
| Editors: water, water Other…, walk (Yoga), custom reading with the icon picker, diet, a too-long name with its message | in-process render | `screenshots/appearance-fixtures/goals-editor-*.png` |
| Account › Daily goals expanded | in-process render | `screenshots/appearance-fixtures/goals-account-*.png` |
| Today and History after a change, and the day before it (standard five) | in-process render | `screenshots/appearance-fixtures/goals-today-*.png`, `goals-history{,-before-change}-*.png` |
| Activity audit ("Walk changed to Yoga · 30 min") | in-process render | `screenshots/appearance-fixtures/goals-history-audit-*.png` |
| Long names in the ring row (scaled, then truncated) | in-process render | `screenshots/appearance-fixtures/goals-rings-long-names-*.png` |
| Repeating extras on Today, Manage extras with captions, the repeat panel for each choice (including Choose days with none, which disables Save) | in-process render | `screenshots/appearance-fixtures/goals-today-repeating-extras-*.png`, `goals-manage-extras-*.png`, `goals-repeat-*.png` |

The in-process renders come from `DAILY_CHALLENGE_SNAPSHOT_DIR=docs/screenshots/appearance-fixtures
swift test --filter "AppearanceTests|DailyGoalsTests"`. The real-popup and welcome captures come from
`scripts/build-proof.sh --adhoc`, then `scripts/capture-real-popup.sh --docs` and
`scripts/test-first-launch.sh --docs`. Both runs refreshed the existing captures as well, because
setup and Manage extras changed.

The probe cannot open popovers, so the editors and Manage extras exist only as in-process renders.

## Only the captain can check

- Opening each editor popover from setup and from Account in the real popup: the popovers should
  appear beside their row, keyboard focus should move to the name field, Return should mean Done and
  Escape should mean Cancel.
- VoiceOver reading the goal rows, the editors' chips and the repeat panel.
- A real start with custom goals, and a later change on two Macs, after the owner has applied the
  [custom goals update](production-sync.md#custom-goals-update-owner-only-once).
- The amber note in Account › Daily goals against a real server that does not have the update yet.

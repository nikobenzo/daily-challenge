# Extras carry-over evidence (11 October 2026)

Captain request: a ticked extra no longer reappears the next day; an open one carries over,
marked with a small "Late" caption. [Day rules](tracker-interface.md#which-days-an-extra-shows).
Worker verification only: offline fixtures, the macOS 27.0.1 (26A434) Mac and a disposable
iPhone 17 / iOS 27 simulator. No real account, device, Keychain, upload or server change.

## Fixture

Both platforms seed the same story through the normal model calls, with a settable fixture clock:
two days before "today", three extras are added and one is ticked; "today" adds a fourth and ticks it.

| Day | Shows |
| --- | --- |
| First day | all three, the ticked one done, no Late |
| Next day (History) | the two open ones, **Late**; the one done earlier is gone |
| Today | the two open ones, **Late**, and today's extra, done, no Late |

Mac: `PopupProbe.seedCarryOver` (probe screen `today-carryover`). iPhone: `PhoneFixtures`
(`todayExtras`, `historyExtras`, `historyCarryOver` and every other extras screen now use it) and
the `-widget-fixture carry-over` variant; `WidgetRenderTests.fixture("carry-over")` mirrors it.

## Tests

- `swift test`: 192 tests passed, including the day-rule tests in
  `Tests/ChallengeCoreTests/ChallengeExtrasTests.swift` (carry-over and Late, past-day corrections,
  archive, earlier every-day histories without rewriting, the open-extras cap, Sydney midnight) and
  `carriedOverExtrasShowLateAndCompletedOnesLeaveLaterDays`.
- `xcodebuild test -scheme DailyChallenge` on the disposable simulator: **TEST SUCCEEDED**,
  37 Swift Testing unit tests (including `phoneCarryOverMarksOpenExtrasLateAndDropsCompletedOnes`),
  6 widget render tests (including `testCarryOverShowsLateExtrasAndDropsCompletedOnes`) and 13 UI
  tests (`testHistoricalExtrasAreLockedUntilEditAndRelockOnSelection` now unticks a past day and
  finds "Stretch, late" locked on the next day). The 5 SpringBoard capture tests skip outside their
  scheme. One earlier run lost keyboard focus once in `testCapAndInvalidTitlesAreExplained`
  (the `today` fixture, unrelated to extras); the full rerun passed.

## Screenshots

| Evidence | Kind | Files |
| --- | --- | --- |
| Mac Today | **real popup** (`screencapture -l`, `"capture": "window-server"`) | `screenshots/real-popup/today-carryover-{light,dark}.{png,json}` |
| Mac Today | in-process render | `screenshots/appearance-fixtures/today-extras-carryover-*.png` |
| Mac History, next day (pill 0/2) | in-process render | `screenshots/appearance-fixtures/history-extras-carryover-*.png` |
| Mac History day popover, next day (Late) and first day (done) | in-process render | `screenshots/appearance-fixtures/history-extras-day-{carryover,first}-*.png` |
| iPhone Today | simulator app | `screenshots/ios/todayExtras-*.png`, `today-extras-detail-*.png`, `today-extras-large-text-*.png` |
| iPhone History, next day (Late) | simulator app | `screenshots/ios/historyCarryOver-*.png`, `history-carryover-large-text-*.png` |
| iPhone History, first day | simulator app | `screenshots/ios/historyExtras-*.png` |
| Extras widget medium/large | in-process render | `screenshots/ios/widgets/rendered-extras-{medium,large}-carry-over-*.png` |
| Extras widget on the Home Screen | placed SpringBoard capture | `screenshots/ios/widgets/home-placed-a-carry-over-*.png` |

The placed captures come from `WIDGET_CAPTURE_MODE=phase5 WIDGET_VARIANTS=carry-over
iOS/scripts/capture-widgets.sh` (layout a placed once, Light then Dark; **TEST SUCCEEDED** both),
where SpringBoard also reads the row as "Stretch, late, pending".

The History popover on the Mac cannot be opened by the real-popup probe, so it is an in-process
render only. Manage extras captures on both platforms were refreshed for the new caption
("To-dos of your own that carry over until done").

## Not covered

Real-phone and two-Mac sync acceptance (owner, [checklist item 10](ios-testflight.md)). The widget
gallery description and the empty widget hint still say "daily"; widget copy was left alone while
two other workers change the widget views.

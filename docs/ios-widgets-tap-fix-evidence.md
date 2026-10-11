# Widget taps: lost and "wrong-row" ticks (11 October)

Report: on the large Extras widget (8 extras, two Cyrillic titles) some taps did nothing and
other rows seemed to change. Evidence: an iPhone 17 / iOS 27 simulator recording on a test account.

## Diagnosis

- **What each tap recorded.** The recorded session's stored history (read-only copy of the
  simulator's App Group) shows one `setExtra` per recorded tap, each for an existing row, and the
  widget redrawing that state about half a second later. No event toggled a row other than its
  intent's own extra ID; the row ID, title and index mapping is intact (Cyrillic included).
- **Trigger.** Taps less than about a second apart. XCUITest hid this: before every event it waits
  for SpringBoard to go idle, i.e. for the previous tap's reload to land. The regression test
  skips that wait only for the rapid taps (private `XCUIApplicationProcess` switches).
- **Mechanism.** Unified logs (chronod, SpringBoard, extension probes) show a lost tap never
  reaches chronod's "Handle interaction": SpringBoard logged *Icon touch began*, chronod reported
  a reload of the Extras timeline, then *Icon touch ended* with no interaction. A press that
  spans a widget re-render is cancelled. `WidgetIntentRunner` called `reloadAllTimelines()` after
  every `perform()`, on top of WidgetKit's own reload of the tapped kind, so each tap re-rendered
  the tapped widget two or three times (and every other Daily Challenge widget once), multiplying
  those windows. The next tap often landed in one: no event (the press "did nothing"), while the
  previous tap's tick appeared late, so the change seemed to belong to the row just pressed.
- **Correct comparison.** The same rows tapped settled (one at a time, each reload landed) always
  flipped exactly the tapped row, before and after.

## Fix

`perform()` no longer reloads every timeline. WidgetKit reloads the tapped widget's kind after
`perform()` returns (logged: one `getTimeline` of that family per tap). Only a recorded pour or
minus also reloads Daily requirements (`WidgetActionRequest.Action.alsoChangedKinds`), whose day
badge and streak follow water. Toggle semantics, binding, retries and storage are unchanged.

One re-render per tap remains (it draws the tick), so a press that lands on that swap can still be
cancelled by SpringBoard when taps come about twice a second; that window is no longer multiplied.

## Results (placed widgets, `-widget-fixture extras-eight`)

Rapid rounds tap seven rows bottom to top with SpringBoard's idle wait skipped.

| Simulator | Pace | Before (blanket reload) | After |
| --- | --- | --- | --- |
| iPhone 17, iOS 27.0 | ~0.55 s apart, 84 taps | 8 lost | 1 lost |
| iPhone 17, iOS 26.4 (animations on) | ~0.55 s apart, 84 taps | 9 lost | 0 lost |
| iPhone 17, iOS 27.0 | ~1 s apart (recording pace), 84 taps | 0 lost | 0 lost |

The iOS 27.0 rows were measured on the branch before the carry-over and widget-animation commits
landed, the iOS 26.4 rows after; neither touches the intent or reload path. Every lost tap was checked against the stored history: none recorded an event, and no event ever
toggled another row. Full `testWidgetTapMapping` after the fix (16 settled extras taps, 14
recording-pace rapid taps, 6 settled and 5 rapid Daily requirements taps): passed with Extras large
(iOS 27.0 and 26.4) and Extras medium (iOS 27.0).

## Reproduction

Disposable simulator only:

```bash
WIDGET_SIMULATOR_ID=<udid> WIDGET_CAPTURE_MODE=taps WIDGET_LAYOUT=c WIDGET_PLACE=1 iOS/scripts/capture-widgets.sh
# layout d = Extras medium; WIDGET_RAPID_ROUNDS=6 WIDGET_RAPID_GAP_MS=0 measures rapid rounds only
```

Unit: `rapidExtraTapsFromOneRenderFlipOnlyTheTappedRow` (every row control from one rendered
entry, eight extras, Cyrillic) and `aWidgetTapReloadsOnlyTheOtherKindsItsEventChanged` in
`iOS/DailyChallengeTests/WidgetActionTests.swift`.

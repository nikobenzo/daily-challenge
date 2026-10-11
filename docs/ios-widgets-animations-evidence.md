# iPhone widget animations: evidence

Branch `fm/dc-widget-animations` (11 October 2026), rebased onto `75659d3` (extras carry-over).
The captain asked for the Water widget's jug to fill after **+** and drain after **−**, and for
must-do and extras ticks to animate instead of switching instantly. Out of scope: the Lock Screen
ring, new widget kinds, app-screen animations and the separate wrong-row tap fix. Intents, toggle
logic, row identity and timeline reloads are unchanged.

## What changed

There are no clocks, timers or loops in the extension. After a tap the intent's timeline reload
replaces the entry, and WidgetKit animates the difference between the two entries.

| Piece | Animation | Reduce Motion |
| --- | --- | --- |
| Jug (`WidgetJugView`, `JugDrawing.framedWater`) | Water level rises or falls to the new total on the app's `WaterMotion` level curve (cubic ease-out, 0.66 s), without the slosh. The flat surface is the gradient under a bottom-anchored scaled mask. | Dissolve (0.2 s), no movement |
| Totals (`WaterWidgetView`) | `numericText` digits roll, in step with the jug, for the total and "ml to go" | Opacity |
| Must-do rings (`RingGauge.fillsDone`, `WidgetRingFill`) | Green stroke fades in on the jug's curve; icon colour darkens; check scales in. Untick reverses it. | Dissolve |
| Extras rows | Filled check springs in from 30 % over the circle; title dims | Opacity |

**Accentable flags must not flip with the entry.** When a view's `widgetAccentable` flag
changed between entries, WidgetKit swapped the whole button in one frame, or cross-faded it
with a ghosted icon. So the extras check is always accentable and only drawn when done.
`RingGauge` is no longer accentable as a whole; the done stroke (`WidgetRingFill`) is a sibling
layer that is always accentable. Tinted Home Screens still mark done rings and ticks
([placed tinted capture](screenshots/ios/widgets/animations/ios26.4-tinted-dark-placed.png)).

**Why the ring fades rather than sweeps.** On placed widgets WidgetKit cross-faded the ring
stroke whatever drove the change: `trim`, two rotating half-plane masks, a bottom-anchored
scaled mask (the jug's technique), and an insertion scale transition, both inside the button
label and as an overlay over the button. The jug's mask, the extras check's scale transition and
the icon colour did interpolate. The ring is therefore a smooth fade. That is a visible
animation, but not the sweep or bottom-up fill first tried.

## Simulator finding: iOS 27.0 animates no widget entry change

On the **iPhone 17 / iOS 27.0 simulator** (runtime 27.0, disposable device) SpringBoard drew
every widget entry change in a single frame. That held for the old build, the new build, and a
bare control widget: a `Text` and `Circle` in system colours, with offset, size and
`numericText` changing on a 2-second timeline and no intent involved. Home Screen transitions in
the same recordings ran at 40–48 frames, so the recorder captures motion.

The same bare widget animated every change (about 30 frames, 0.5–0.8 s) on an **iPhone 17 /
iOS 26.4 simulator**. All motion evidence below is therefore from iOS 26.4. On iOS 27.0 the
widgets reach the correct final state ([iOS 27.0 strip](screenshots/ios/widgets/animations/ios27.0-light.png):
the jug, drain and ring each jump in one frame).

**Real-phone check needed.** Whether iOS 27 on a device animates widget entries is unverified.
If it behaves like the simulator, no widget animation (default or custom) will be visible on
that phone, and that would match the captain's "it just adds instantly".

## Evidence (iOS 26.4 simulator, placed widgets)

Each sheet has four rows of 12 frames, 67 ms apart, from just before the change:

1. jug after **+**
2. jug after **−**
3. walk ring
4. "Read a chapter" extra

They are cut from `simctl io recordVideo` recordings of the real Home Screen. The recordings
were resampled to 60 fps and cropped to the widgets. The frames come from SpringBoard, not
in-process renders.

| Sheet | Notes |
| --- | --- |
| [Light](screenshots/ios/widgets/animations/ios26.4-light.png) | Fill, drain, ring fade-in with check, extras check springing in |
| [Dark](screenshots/ios/widgets/animations/ios26.4-dark.png) | Row 3 is the walk untick (fade out); that run's tick was drawn in two frames (see below) |
| [Light, Reduce Motion](screenshots/ios/widgets/animations/ios26.4-light-reduce-motion.png) | Jug dissolves between levels, ring and check fade, no scaling |
| [Dark, Reduce Motion](screenshots/ios/widgets/animations/ios26.4-dark-reduce-motion.png) | As Light |
| [Old build, tinted](screenshots/ios/widgets/animations/old-build-ios26.4-tinted.png) vs [new build, tinted](screenshots/ios/widgets/animations/new-build-ios26.4-tinted.png) | The same tinted Home Screen. The old build already got WidgetKit's default animation of the jug path and a plain check fade on iOS 26.4. Its ring cross-faded with a ghosted icon. Rows 1 and 2 of the old sheet are the same **+** (that run recorded no animated **−**). |

The clips [Light](screenshots/ios/widgets/animations/ios26.4-light.mp4) (30 s) and
[Light, Reduce Motion](screenshots/ios/widgets/animations/ios26.4-light-reduce-motion.mp4)
(18 s) are the cropped recordings: **+**, **+**, **−**, walk on and off, an extra on and off.

**Missed animations.** Occasionally a reload is drawn in one or two frames: the first tap of a
run, and the dark run's walk tick. Every later tap in the same runs animated.

**Wrong-row taps.** Some recorded extras taps toggled a different row or reverted. That is the
separate wrong-row tap bug, not touched here.

## Reproduction

```bash
# Disposable simulators only (never a booted device another lane uses). Places layout a first.
WIDGET_SIMULATOR_ID=<udid> WIDGET_CAPTURE_MODE=animations WIDGET_PLACE=1 APPEARANCE=light \
  REDUCE_MOTION=disabled bash iOS/scripts/capture-widgets.sh
```

`testWidgetAnimations` reseeds the `partial` fixture and taps **+**, **+**, **−**, walk twice
and "Read a chapter" twice, pausing 4 s after each tap. The script records the screen to
`.build/widget-animations-<appearance>-<time>.mov`. `REDUCE_MOTION` writes the simulator's
accessibility preference and restarts SpringBoard. The placed captures it exports
(`home-placed-animations-after-*`) were not committed.

## Checks

- `swift test`: passed, 192 tests (47 tracker-interface, 5 probe, 9 proof-auth, 63 sync-kit, 68 core).
- `xcodebuild test -scheme DailyChallenge` on the iOS 27.0 simulator: passed, 37 Swift Testing and
  6 `WidgetRenderTests` unit tests, and 13 app UI tests. The 6 opt-in SpringBoard capture tests
  skip in this scheme, including the new `testWidgetAnimations`.
- Both suites were rerun on the rebased tree.

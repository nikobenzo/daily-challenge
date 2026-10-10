# Phase 5: widget polish, accessibility and Lock Screen evidence

Implementation: `b6a0c9c` on `fm/dc-iphone-widgets-p5` (10 October 2026). Phase 5
only: visual parity, VoiceOver, text size, contrast, transparency and tinted rendering, the
D-W2 read-only Lock Screen water ring, the Manage extras field fix and release documentation.
No new widget kind, Lock Screen extras or requirements, upload, signing or Mac UI change.
`VERSION` (0.3.0 (3)), Keychain identifiers, store format, transport and intents are unchanged.

## What changed

| Piece | Change |
| --- | --- |
| `Sources/DailyChallengeProof/Shared/JugDrawing.swift` | The jug drawing (vessel, water, handle, cap, overflow drops) moved out of `WaterJugView` unchanged, so the widget draws the same jug without the motion clocks. `WaterJugView` animates it exactly as before. |
| `SharedComponents.swift` `RingGauge.labelFont` | Optional label font, defaulting to `Theme.Fonts.ringLabel`, so the Mac and app are unchanged. Widgets pass a text-style font (see [large text](#large-text)). |
| `iOS/DailyChallengeWidgets/WidgetViews.swift` | Water: the design jug, hero total, "ml to go" line, gradient **+ 450 ml** pill (quiet tinted pill once the goal is met) and round − button. Requirements: Day badge, streak flame, date, and four `RingGauge`s (dumbbell, walker, leaf, book) in the Today colours with check/dash/× glyphs. Extras: the app's checklist rows (green filled check / empty circle, dimmed title when done). Signed-out, setup and unavailable states use the app mark with a calm message. Lock Screen: `WaterAccessoryView`. |
| `ChallengeWidgets.swift` | `WaterWidget.supportedFamilies` adds `.accessoryCircular`; the description says the Lock Screen shows today's total only. |
| `iOS/DailyChallenge/PhoneExtrasViews.swift` | Manage extras **New extra** and rename fields use the design field (field fill capsule, hairline border, focus ring) instead of the system rounded border that drew a black box in Dark. |
| `scripts/ios-archive.sh --check` | Also scans every extension file for configuration or credential files, the configured `.env.local` values (compared without printing), real secret-key and JWT shapes, `service_role` and private keys. |
| Fixtures, tests, capture helpers | `-widget-fixture signed-out`, `setup`, `unavailable`; `long-names` is now ten 40-character titles. `WidgetRenderTests` adds the Phase 5 matrix. `WidgetPlacementUITests.testPhase5Home` / `testPhase5LockScreen`, `capture-widgets.sh` modes `phase5` and `lock`, and `capture-screenshots.sh CAPTURE_PHASE5_ONLY=1`. After F, the Phase 3 gallery test gained the bounded search retry and the Phase 4 actions test reuses `addWidget` (see F); a Phase 4 unit test no longer gives two devices' edits the same instant (see C). |

## Visual parity with the app and the Mac

Compare the placed widgets with the app's Today ([today-light](screenshots/ios/today-light.png),
[today-dark](screenshots/ios/today-dark.png)) and the Mac popup
([today-light](screenshots/real-popup/today-light.png),
[today-extras-dark](screenshots/real-popup/today-extras-dark.png)):

| Element | App / Mac | Widget (placed: [Light](screenshots/ios/widgets/home-placed-a-partial-light.png), [Dark](screenshots/ios/widgets/home-placed-a-partial-dark.png)) |
| --- | --- | --- |
| Jug | `WaterJugView`: glass vessel, gradient water, handle, cap, highlight; drops below when over 4 L | Same `JugDrawing`, scaled to 124 pt (medium) or 68 pt (small), still; overflow drops shown ([overflow](screenshots/ios/widgets/home-placed-a-overflow-light.png)). |
| Total | `2,250 ml` heavy rounded, `/ 4,000` caption (green once met) | Same, plus "1,750 ml to go · 4 L goal" or "Goal met · 4 L" on medium. |
| Pour controls | Round − , gradient **+ 450 ml** pill, quieter pill after the goal | Same shapes and tokens; no custom-pour (⋯) button (not a widget action). |
| Requirement rings | `RingGauge`, 64 pt, stroke 6, icons dumbbell / figure.walk / leaf / book, green done + check, dash pending, dashed red × missed | The same `RingGauge` and icons. Water is the jug widget, so the requirements widget shows the other four. |
| Day / streak | Day badge, flame `6 / 75 days` | Day badge (green with check when all five are done), flame `0 / 75`, plus the challenge date and city. |
| Extras | Checklist rows: 24 pt green filled check / empty circle, dimmed done title; header "Extras · 1/3" (phone) or eyebrow + count badge (Mac) | Same rows at 21 pt with the phone's "Extras · 1/3" header. |
| Surface | Glass card over the backdrop | Opaque `solidGlass` (the design's standalone/Reduce Transparency tint), so no translucency is needed. |

Before Phase 5 the widgets used a generic bottle, plain circles and plain text: see
`git show 8b6310c:docs/screenshots/ios/widgets/home-placed-actions-before-light.png` (the file
itself is re-captured by this phase).

## Accessibility

**VoiceOver.** Labels read from SpringBoard's accessibility tree on placed widgets (asserted by
`testPhase5Home` and `testPhase5LockScreen`; the trees are attached to the xcresult):

- Water: "Water, 2,250 of 4,000 millilitres" (uncapped: "4,500 of 4,000 millilitres, goal
  exceeded"); controls "Add 450 ml" and "Undo latest pour" ("Undo latest pour, no pour today"
  when disabled). Lock Screen ring: "Water, 2,250 of 4,000 millilitres".
- Requirements: "Workout, 45 min · home / gym, done", "Walk, 45 minutes, pending",
  "Clean diet, your own rules, done", "Bible, 10 pages, pending"; a missed diet reads
  "Clean diet, missed. Opens Daily Challenge to change it". "Day 1 of 75", "Current streak: 0 days".
- Extras: the full title and state even when the row is truncated ("10. Prepare tomorrow's
  healthy lunch box, pending"); header "Extras, 1 of 10 done"; "Open all 10 extras".
- States: "Daily Challenge, Open Daily Challenge to sign in" (or "to set up", or "Open Daily Challenge").

<a id="large-text"></a>**Large text.** Widget text uses text styles that follow the widget's Dynamic Type size.
Water stops growing at the largest standard size; the date label and Day/streak header cap at
extra-extra-large and give way first; ring labels cap at extra large (fixed 64 pt rings in four
columns). At accessibility sizes Extras shows five rows (large) or one (medium) and keeps
**Open all N extras**. A placed capture at accessibility XXXL found that `RingGauge`'s
`Theme.Fonts` label scales with the extension process's text size and ignores the widget cap,
pushing the row off the widget; in-process renders could not show this (they use the test
host's size). `RingGauge.labelFont` fixed it, verified in the placed `-text-ax3` captures.

**Increase Contrast** (simulator setting, placed): the jug outline switches to `textPrimary`
through `JugDrawing`; rings keep glyphs. **Reduce Transparency**: the widget surface is already
opaque; the jug glass switches to `solidGlass` (in-process render only: the simulator has no
command-line Reduce Transparency switch). **Tinted and Clear Home Screens** (placed, switched
through SpringBoard's Customise sheet): accented rendering keeps the jug level, done rings and
ticks (accentable), dash/check glyphs, and a translucent pour pill with full-opacity text.
iOS draws the non-accented group brighter than the tinted one, so in tinted mode a pending
ring's label reads brighter than a done ring's; the check, dash and × glyphs carry the state.

**Tap targets.** Rings are 78 × 84 pt buttons, extras rows the full width × 27–28 pt, water
controls 36–40 pt high; overflow and the missed diet open the app.

## Lock Screen ring (D-W2)

`accessoryCircular` on the Water widget: a capacity gauge of today's water clamped at 4 L,
litres to one decimal rounded down (2,250 ml reads 2.2; 3,990 never reads 4.0; 4,500 reads 4.5)
and a drop. No controls and no binding: it is read-only. The whole surface is
`privacySensitive()`, so iOS redacts it on a locked phone. Signed-out/setup/unavailable show a
plain drop with no data.

The simulator Cover Sheet has no passcode, so it shows the unlocked presentation only. The
redacted rendering is an in-process render (`rendered-lock-water-circular-redacted.png`);
real locked-phone redaction is owner acceptance.

## Environment and commands

Xcode 27.0 (27A266a); iPhone 17 / iOS 27.0 (24A434). Disposable simulators created for this
task: **Daily Challenge Phase 5** (`D3FBDCBC-BA64-469C-83F1-6B2354D01CA9`, SpringBoard captures,
erased before every run) and **Daily Challenge Phase 5 App** (`17D92EB8-754D-4CCF-A754-CCE7848AFB7F`,
C and D). Synthetic fixtures, temporary roots, fake auth and transports only. No real account,
production Keychain, installed Mac app, signing, upload or network service was used. The
authorized public `.env.local` was copied without printing it and stays ignored.

- **A:** `(cd iOS && xcodegen generate)`; the project gains `SharedComponents.swift` and
  `JugDrawing.swift` in the extension. Committed with the YAML.
- **B:** `swift test`: **passed, 185 tests** (46 tracker-interface, 5 probe, 9 proof-auth,
  63 sync-kit, 62 core), including the Mac appearance tests over the moved jug drawing.
- **C:** `xcodebuild test -project iOS/DailyChallenge.xcodeproj -scheme DailyChallenge
  -destination 'platform=iOS Simulator,id=17D92EB8-754D-4CCF-A754-CCE7848AFB7F'
  -derivedDataPath .build/ios-test-derived -collect-test-diagnostics never
  -resultBundlePath .build/p5-final-phone.xcresult`: **passed, 41 unit tests** (36 Swift
  Testing plus 5 `WidgetRenderTests`) **and 13 app UI tests**; the 5 opt-in SpringBoard capture
  tests skip in this scheme. Rerun on the final tree after the harness fixes
  (`-resultBundlePath .build/p5-final-c.xcresult`): **passed**, same counts. One earlier final
  rerun failed `widgetAndAppEditsInterleaveThroughFreshTransactions` (Phase 4): with the fixed
  test clock, the app's and the widget's toggles shared one instant, so their order fell to the
  random per-run device IDs. The test now advances its clock between edits (test-only; product
  ordering is unchanged; real clocks make such a tie practically impossible); 12 of 12 isolated reruns passed.
- **D:** `DEVICE="Daily Challenge Phase 5 App" CAPTURE_WAIT=9 CAPTURE_PHASE5_ONLY=1 bash
  iOS/scripts/capture-screenshots.sh`: Manage extras Light/Dark, empty and large text. (A first
  run with the default 3 s wait captured mid-animation frames under load; they were replaced.)
- **E:** `bash scripts/ios-archive.sh --check`: **passed**, unsigned Release `0.3.0 (3)`:
  embedded extension, bundle ID, WidgetKit point, matching versions, five non-discoverable
  intents in the extension only, no Sparkle, and the new scan ("no configuration, credentials or
  5 configured values"). A planted copy of the configured URL in a scratch copy of the extension
  was rejected. The extension links supabase-swift through ChallengeSyncKit (unchanged since
  Phase 3) without calling it; the scan matches key shapes because the SDK names the
  `sb_secret_` prefix itself.
- **F:** SpringBoard capture series (below), each on a freshly erased simulator.

F ran as 22 `capture-widgets.sh` runs (Light then Dark), each on a freshly erased simulator:
layout a (all 13 variants), layout b (9), accessibility XXXL text for both layouts, Increase
Contrast, tinted Home Screen, Lock Screen, gallery and the Phase 4 actions regression, then
extra-extra-extra-large text for both layouts (Light) and the Clear Home Screen (Dark).
**19 passed first time.** Three failed in SpringBoard navigation, not in a widget: Dark gallery
and Dark actions found no gallery search result just after install (those two tests lacked the
search retry the Phase 5 placement helper already had; the actions test now reuses
`addWidget`, the gallery test gained the same bounded retry), and Light XXXL layout b landed one
gallery page off after four swipes. **All three passed on rerun** (fresh erase, same settings), so every listed capture comes from a passing run.
Each passing `testPhase5Home` / `testPhase5LockScreen` asserted the VoiceOver labels listed under [Accessibility](#accessibility) on
the placed widgets.

## Capture provenance

All under [screenshots/ios/widgets/](screenshots/ios/widgets/) unless noted. Every placed
widget shows synthetic fixture data on an actual simulator Home Screen or Cover Sheet, driven
only by XCUITest; none is owner device evidence.

- **Placed Home Screen (actual SpringBoard, XCUITest):**
  `home-placed-a-<variant>-{light,dark}.png` for partial, empty, full, overflow, pending,
  complete, missed, extras-empty, extras-ten, long-names, signed-out, setup and unavailable
  (layout a: Water, Daily requirements, Extras medium); `home-placed-b-<variant>-{light,dark}.png`
  for the same except full/pending/complete/missed (layout b: Water small, Extras large);
  `home-placed-{a,b}-{partial,extras-ten}-text-ax3-{light,dark}.png` (accessibility XXXL) and
  `-text-xxxl-light.png` (largest standard size);
  `home-placed-a-{partial,missed}-increase-contrast-{light,dark}.png`;
  `home-placed-a-{partial,missed,complete}-tinted-{light,dark}.png` and
  `home-placed-a-partial-clear-dark.png`, with the Customise sheet in
  `home-customize-{tinted-light,tinted-dark,clear-dark}.png`; the Phase 4 regression
  `home-placed-actions-{before,after}-{light,dark}.png` and
  `app-{today,history}-after-widget-actions-{light,dark}.png`.
- **Placed Lock Screen (actual Cover Sheet, XCUITest):**
  `lock-placed-water-{partial,empty,overflow,signed-out}-{light,dark}.png`. The Lock Screen
  takes its colours from the wallpaper, so Light and Dark look the same.
- **Image size:** headline captures stay full resolution (1206 × 2622):
  `home-placed-a-partial-{light,dark}`, `home-placed-a-partial-tinted-{light,dark}` and
  `lock-placed-water-partial-{light,dark}`. The rest of the placed and gallery set is
  downscaled to half (603 × 1311) with `sips -Z 1311` to keep the repository small.

- **Gallery (actual SpringBoard widget gallery, synthetic placeholder entries):**
  `gallery-{water-small,water-medium,requirements-medium,extras-medium,extras-large}-{light,dark}.png`
  and `lock-gallery-water-circular-{light,dark}.png` (Lock Screen picker preview, 0.0).
- **Rendered (in-process `ImageRenderer`, not Home Screen):** `rendered-*.png`, 89 images from
  C: water small/medium empty/partial/full/overflow, requirements pending/complete/missed,
  extras medium/large empty/partial/ten/long names/overflow, states small/medium, large text
  (xxxLarge, accessibility3), Increase Contrast, Reduce Transparency, the Lock Screen ring
  (empty/partial/overflow) and the privacy-redacted ring and medium water. Renders use the
  test host's text size for `Theme.Fonts`, so they understate accessibility sizes (see above).
- **App (actual simulator app):** `../manage-extras{,-empty,-large-text}-{light,dark}.png`.

## Reproduce

```bash
export WIDGET_SIMULATOR_ID=<disposable iPhone 17 / iOS 27 udid>   # erase before each run
WIDGET_CAPTURE_MODE=phase5 WIDGET_PLACE=1 WIDGET_LAYOUT=a \
  WIDGET_VARIANTS=partial,empty,full,overflow,pending,complete,missed,extras-empty,extras-ten,long-names,signed-out,setup,unavailable \
  APPEARANCE=light bash iOS/scripts/capture-widgets.sh
WIDGET_CAPTURE_MODE=phase5 WIDGET_PLACE=1 WIDGET_LAYOUT=b WIDGET_VARIANTS=partial,extras-ten APPEARANCE=dark \
  CONTENT_SIZE=accessibility-extra-extra-extra-large WIDGET_TAG=text-ax3 bash iOS/scripts/capture-widgets.sh
WIDGET_CAPTURE_MODE=phase5 WIDGET_PLACE=1 WIDGET_HOME_STYLE=tinted WIDGET_TAG=tinted \
  WIDGET_VARIANTS=partial APPEARANCE=light bash iOS/scripts/capture-widgets.sh
WIDGET_CAPTURE_MODE=lock WIDGET_VARIANTS=partial,overflow,signed-out APPEARANCE=dark bash iOS/scripts/capture-widgets.sh
```

Each `xcodebuild test` reinstalls the app, which removes placed widgets, so every run places its
own layout (`WIDGET_PLACE=1`). Layout a places Water, Daily requirements and Extras medium;
layout b Water small and Extras large. After an app launch, Home returns to the app page, so the
test looks one page either side for the widgets. A freshly installed extension can take a few
seconds to reach the gallery search; the test retries the search up to three times. The
simulator's British locale labels the sheet **Customise**. Lock Screen: pull down the Cover
Sheet, long-press, Customise → Lock Screen → the widget area → Daily Challenge → the circular
preview, close the picker, Done, then choose the edited poster.

## Limitations and owner acceptance

- Simulator only: no signed App Group authorization, locked-phone redaction, passcode Lock
  Screen, WidgetKit refresh cadence or real VoiceOver speech. Labels are read from the
  accessibility tree, not heard.
- Reduce Transparency and the redacted ring are in-process renders.
- Already-queued water reminders can still arrive after a widget reaches 4 L until the app runs.
- The owner steps and the real-phone checklist are in
  [TestFlight guidance](ios-testflight.md#widget-release-owner-steps-and-real-phone-acceptance).

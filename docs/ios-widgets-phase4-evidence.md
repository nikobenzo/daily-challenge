# Phase 4: widget App Intents and sync hand-off evidence

Implementation: `9de46fae14ed3d99e9149bbb33cd01695dda6c87` on `fm/dc-iphone-widgets-p4`
(10 October 2026). Phase 4 only. The three widgets log today's events from the Home Screen
while the app is suspended or terminated. No Lock Screen family, extension networking, shared
credentials, custom water input, historical corrections or extras management was added.
`VERSION`, Mac sources/paths, Keychain identifiers, `SupabaseChallengeTransport` and the
snapshot format are unchanged.

## What was built

| Piece | Behaviour |
| --- | --- |
| `iOS/Shared/WidgetActions.swift`: `WidgetActionRequest`, `WidgetActionRecorder` | Compiled into the app (for tests) and the extension. Parses only `Challenge.Habit` raw values, extra UUIDs and the opaque generation/challenge UUIDs: no owner, date, amount or path. Records `.pour(450)`, `.undoLatestPour`, `.setHabit`, `.setDiet` and `.setExtra` through `ChallengeStore.record` and nothing else. |
| `PhoneSharedStore.transaction(generation:challengeID:)` | Reads the published account under the shared lock. Refuses unless generation and challenge both match the binding, then fresh-loads that owner's store. Metadata is not rewritten. |
| `iOS/DailyChallengeWidgets/WidgetIntents.swift` | `PourWaterIntent`, `UndoWaterIntent`, `ToggleHabitIntent`, `SetDietIntent`, `ToggleExtraIntent`. Extension only, `isDiscoverable = false`. Each `perform()` calls the recorder with a fresh event ID and reloads all timelines. |
| `WidgetViews.swift` | `WidgetControl` wraps rows in `Button(intent:)` in the extension (`WIDGET_EXTENSION` flag). The app's in-process renders draw the same label. Water: + 450 ml and − on both families. Requirements: the three habits and the diet row. Extras: each visible row. |
| `ChallengeWidgetEntry.binding` | Opaque generation + challenge ID from published metadata. Nil for placeholders, gallery previews, signed out, no challenge and unavailable states, which therefore stay read-only. |

Rules as implemented:

- **Transaction:** the recorder re-reads today's summary inside the lock. It captures
  execution time once after acquiring it and computes the day in the challenge zone. A rendered
  completion, amount or day is never authoritative.
- **Water:** plus always records 450 ml, including past 4,000 ml. Minus targets today's latest
  active pour, including another device's synced custom pour. With no pour today, minus is drawn
  disabled; a stale invocation returns `.unchanged`, with no event, no error and no reload.
- **Diet (D-W1):** pending ↔ clean. A stored missed day returns `.openApp` without an event. A
  missed row is drawn as a link to `daily-challenge://today` rather than an intent button.
- **Extras:** an extra must be in today's summary. Archived or unknown extras are refused and
  the widget reloads.
- **Binding:** an app relaunch, account switch or sign-out publishes a new generation (or no
  account), so earlier rendered controls are refused as `staleAccount`. Dormant history is
  untouched.
- **Retries:** each `perform()` generates one event ID. A repeat of the same invocation finds
  that ID already committed and adds nothing; a toggle is not flipped back. Distinct taps stay
  distinct. A render-time ID would have merged distinct taps, because intent parameters are
  archived with the timeline. App Intents documents no automatic retry or exactly-once delivery
  for widget buttons, and none is claimed: an extension killed after commit but before
  returning could, if the system re-ran it, record a second event.
- **Failures:** `perform()` never reports success it did not commit. Errors leave history byte
  for byte unchanged; the reload shows the stored state, or "Open Daily Challenge" when storage
  is unreadable. Buttons are used instead of intent `Toggle`s, which WidgetKit flips
  optimistically before `perform()` finishes.
- **Hand-off:** extension writes join the normal pending queue. `PhoneApp.becameActive` reloads
  through the Phase 2 seam (which reconciles water reminders) and requests sync.
  `backgroundRefresh` reloads and calls `sync(force:)`. Sync reads pending under the lock,
  uploads with the app's authenticated transport and merges fresh. Only IDs the fetch returns
  are acknowledged.
- **Ordering:** two events with an identical timestamp keep the existing
  (timestamp, device, event ID) order rather than tap order. Real taps have distinct instants.

## Environment and commands

Xcode 27.0 (27A266a); iPhone 17 / iOS 27.0 (24A434). All runs used the disposable
**Daily Challenge Phase 4** simulator, UDID `088A2050-D49E-4E7F-BCDD-46BF76B0C3F6`, created
for this task and erased before each SpringBoard capture. Hosted tests use temporary roots,
injected clocks, synthetic accounts and in-memory transports. No real account, production
Keychain, installed Mac app, hosted migration or upload was used. The authorized public
`.env.local` was copied without printing it and remains ignored.

- **A:** `(cd iOS && xcodegen generate)`. The regenerated project matches the committed YAML
  (re-running it produced no change).
- **B:** `swift test`. **Passed: 185 tests** (46 tracker-interface, 5 probe, 9 proof-auth,
  63 sync-kit, 62 core). The two Mac `PopupResizeTests` failures recorded in Phase 3 did not
  recur on this run.
- **C:** `xcodebuild test -project iOS/DailyChallenge.xcodeproj -scheme DailyChallenge
  -destination 'platform=iOS Simulator,id=088A2050-D49E-4E7F-BCDD-46BF76B0C3F6'
  -derivedDataPath .build/ios-test-derived -collect-test-diagnostics never
  -resultBundlePath .build/p4-final-phone.xcresult`. **Passed: 37 unit tests** (36 Swift
  Testing, including 11 new `WidgetActionTests`, plus the 44-image render matrix) **and 13 app
  UI tests**. The 3 opt-in SpringBoard capture tests were skipped in this scheme.
- **E:** `bash scripts/ios-archive.sh --check`. **Passed**, unsigned Release `0.3.0 (3)`.
  Phase 3 checks plus a new assertion: exactly the five intents, none discoverable, are in the
  extension's `Metadata.appintents`, and the app bundle ships no App Intents metadata.
- **F (placed Home Screen, actual SpringBoard):**
  `WIDGET_SIMULATOR_ID=<udid> WIDGET_CAPTURE_MODE=actions APPEARANCE=light|dark bash iOS/scripts/capture-widgets.sh`.
  **Passed in Light and Dark.** Gallery refresh:
  `WIDGET_CAPTURE_MODE=gallery APPEARANCE=light|dark bash iOS/scripts/capture-widgets.sh`.
  **Passed in both appearances.**

## Offline end-to-end simulator test

`WidgetPlacementUITests.testWidgetActionsOffline` drives only SpringBoard through XCUITest,
with no external screen-control tool:

1. Launch `-widget-fixture partial` (2,250 ml, workout and clean diet, extras 1/3), then Home.
2. Edit → Add Widget → Daily Challenge. Assert and add the Extras medium, Daily requirements
   medium and Water medium gallery pages. Done.
3. `app.terminate()` and assert the app is **not running**.
4. Tap the placed widgets' own controls, found by their accessibility labels in SpringBoard:
   *Read a chapter, pending* → *Walk · 45 min, pending* → *Add 450 ml* ×2 → *Undo latest pour*.
   The app is still not running afterwards, so every write ran in the extension.
5. Wait for SpringBoard to show `2,700 ml` and `Extras · 2/3`, then capture.
6. Relaunch with the new `-widget-fixture reopen`, which reopens the same fixture group
   without reseeding. Assert Today reads `2,700 of 4,000 millilitres`, walk `Complete` and
   `Extras, 2 of 3 done`, then capture Today and History.

Both appearances passed. Placement succeeded this time; Phase 3's two placement attempts had
failed. One fresh-boot run dropped the first Add Widget tap; a single bounded retry of
Edit → Add Widget now precedes failure. When the extras row was tapped last, SpringBoard's
accessibility tree already read 2/3 while the captured pixels still showed 1/3, even several
seconds later. Tapping extras first and awaiting the water total last produces captures in
which every widget shows its committed state. The data was correct in every run, as the app
assertions confirm.

Catch-up uses fake servers in unit tests, because the simulator test is offline by design.
After a widget edit during an in-flight upload, merge keeps the widget event pending. An
uploaded event the fetch omits stays pending. The next sync clears only fetched IDs.

## Unit acceptance coverage (`WidgetActionTests`)

- Every intent action records the expected existing `Challenge.Action`, today's challenge day,
  `recordedAt` equal to the injected execution time and the shared store's existing device ID.
  The pending count rises by one and the timelines reload. Minus's `undonePourID` is the
  concrete latest pour.
- No-pour minus: `.unchanged`, snapshot bytes identical, yesterday untouched, no reload.
  Plus past 4 L: 4,500 → 4,950 ml, shown uncapped in the provider entry.
- Synced custom-pour undo: another device's later 300 ml pour is undone first, then the local
  450 ml pour, then a no-op.
- Rapid taps: 24 concurrent pours through two independent accessors produce 24 distinct events.
  A retried invocation ID adds nothing for a pour or a toggle.
- Archived and unknown extras are refused. Forged generation or challenge IDs are refused with
  bytes unchanged. Malformed parameters (`outdoorWorkout`, `Walk`, a path, a non-UUID
  generation, empty IDs) do not parse.
- Corrupt snapshot or corrupt metadata, a missing App Group (nil root) and protected data all
  throw. Bytes are preserved and the widget then shows the calm unavailable state with no
  binding.
- A relaunch's new generation, an account switch and sign-out each refuse old controls. No
  other account's history is written. Signed-out entries carry no binding; placeholders never do.
- Midnight between render and tap: an entry rendered at 23:59 on 9 Oct (Jersey) is tapped at
  00:01. The tick records on 10 Oct as a fresh completion, minus is a no-op and yesterday keeps
  2,000 ml and its tick.
- Diet goes pending → clean → pending. A missed day returns `.openApp` with bytes unchanged.
- Concurrent app edits: the app's stale toggle reads the widget's untick; 20 widget pours and
  20 app pours interleave without loss.
- In-flight sync and catch-up, as described above.
- Foreground and background hand-off: nine widget pours reach 4,050 ml while the app's model is
  stale. `becameActive()` shows them and removes today's queued reminders. `backgroundRefresh()`
  uploads widget events through the fake transport and clears the pending queue.

## Capture provenance

All PNGs are under [screenshots/ios/widgets/](screenshots/ios/widgets/).

- **Placed Home Screen captures (actual SpringBoard, fixture data):**
  `home-placed-actions-before-{light,dark}.png` (2,250 ml, walk pending, extras 1/3) and
  `home-placed-actions-after-{light,dark}.png` (2,700 ml, walk ticked, extras 2/3) were taken
  with the app terminated.
- **App after relaunch (actual simulator app, same fixture history):**
  `app-today-after-widget-actions-{light,dark}.png` and
  `app-history-after-widget-actions-{light,dark}.png` show the same values in Today and History.
- **Gallery (actual SpringBoard widget gallery, synthetic placeholder entries):**
  `gallery-*-{light,dark}.png`, all five families, re-captured so they show the new controls.
  Previews carry no binding and are read-only.
- **Rendered snapshots (in-process `ImageRenderer`, not Home Screen):** `rendered-*.png`
  re-exported from C. Water and requirements variants changed (controls, untinted missed-diet
  link); extras renders are byte-identical to Phase 3.

## Limitations and owner acceptance

- A widget reaching 4,000 ml cannot cancel already-queued water reminders. They remain until the
  app next runs (foreground or iOS-selected refresh), which reconciles them. Widgets never
  request notification permission or change reminder preferences.
- Success means durably saved on the phone, not uploaded. Upload waits for app execution, and
  iOS refresh is best effort.
- After sign-out or an account switch, controls are refused at once. Already-rendered widget
  images can persist until WidgetKit reloads; privacy-sensitive content and no email reduce
  exposure.
- The simulator does not prove signed App Group authorization, locked-device behaviour or
  WidgetKit cadence on a real phone. There are no new Apple portal steps beyond Phase 3. Real
  authenticated sync is owner acceptance on a disposable test account (see
  [TestFlight guidance](ios-testflight.md)).

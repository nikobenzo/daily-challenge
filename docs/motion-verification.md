# Bounded motion and celebrations — 8 October 2026

## Implementation

- `WaterJugView` draws a 1.2-second eased rise/fall and damped slosh. Increasing water beyond 4,000 ml adds transient droplets within its clipped 190-point surface. Interrupted pours/undo start from the last displayed interpolated level; overflow eligibility still compares saved amounts. The actual ml label and jug accessibility value always use the saved amount, not the interpolated level. Excess water is never discarded.
- `TrackerMotion.swift` owns finite 30 fps frame dates and a cancellable frame-delivery task. Each effect has one finite task, which clears its presentation state at the deadline. **No TimelineView, display-link subscription, repeating timer or idle animation remains.** Missed frames are skipped instead of delivered in a burst. Date comparisons, rather than subtraction against fractional seconds, enforce deadline boundaries.
- `PopupVisibilityReader` observes the host window's native occlusion state. Closing/occluding the retained popup removes effects and cancels their tasks; reopening does not replay them. `onDisappear` is an additional cancellation path. Native popup lifecycle acceptance remains an owner check.
- A newly completed local **today** can show a 1.8-second daily badge/sparkles; a newly derived 75-day milestone gets a stronger 3-second trophy/sparkles effect. No sound. Both effects are clipped to the jug area and disable hit testing.
- `CelebrationLedger` stores `celebrations-<owner UUID>.json` alongside, but separate from, challenge history. Keys include immutable challenge ID, challenge day (in the challenge's timezone) and achievement kind. Open/reload, sync, import and historical correction consume observed completions without emitting effects. A successful local incomplete→complete transition on today is the only emission path. Markers survive undo, correction, reopening and relaunch, and are neither synced nor included in portable backups. They represent device-local presentation history, not challenge progress.
- The ledger is atomically persisted **before** an effect is emitted. Corruption or write failure suppresses effects rather than risking replay; challenge saving remains independent. Do not delete the ledger to troubleshoot challenge data.
- Live system Reduce Motion cancels slosh/spills and uses immediate static water levels plus a subtle, finite completion badge. A fixture-only environment override tests this without changing macOS settings. Primary text/particles and semantic badge backing remain legible in Light/Dark/Increase Contrast. The production full-window popup backing is unchanged.

## Automated verification

The pre-review `swift test` run recorded **97 passing test definitions** (41 interface, 6 auth, 9 probe, 41 challenge-core), before the interruption regressions below were added. This is historical evidence, not a current suite count.

`Tests/TrackerInterfaceTests/MotionTests.swift` executes:

- rise/fall, rapid pour/undo and successive-pour level continuity, saved-amount overflow eligibility, finite deadlines, hidden and Reduce Motion policies;
- actual asynchronous frame delivery ending and cancellation preventing later writes;
- daily persistence, reopen/relaunch, sync/open/import baselining, undo/recompletion, past-day corrections and Jersey midnight;
- derived 75-day milestones, including a historical correction that newly derives today's milestone but must not celebrate it;
- corrupt/unwritable marker fail-closed behavior and the real `TrackerModel` local command path;
- native hit testing through active overflow/celebration overlays, including changing the injected Reduce Motion policy while active.

Existing production-root backing/oversized-host and Light/Dark renders still pass. These are **in-process supporting evidence**, not screen captures, actual popup compositing acceptance, or proof of real-system Increase Contrast behavior. No system accessibility settings were changed.

## Fixture CPU measurements — acceptance remains incomplete

Run from an isolated checkout:

```bash
bash scripts/profile-motion-fixture.sh
```

The script builds an optimized, separately ad-hoc-signed `app.daily-challenge.motion-fixture` bundle under `.build/motion-fixture`. It compiles the production motion/visibility views and pure challenge rules, but **does not link auth, Keychain, network, production data access, reminders or the 30-second sync poller**. Values are synthetic and fixture output stays in the checkout. Only its own bounded floating native window is shown/hidden; the captain's app is never stopped or replaced. The fixture is not the complete MenuBarExtra app, so these measurements isolate animation overhead, not whole-app energy.

The primary measurement is the change in cumulative process user+system CPU from `getrusage`, divided by wall time: **not** the decaying `%CPU` reported by `ps`. One CPU core at saturation is 100%. The script also records supplementary `ps` samples. It measures hidden, idle-open, ten repeated pour/undo + daily/milestone effects, settled, and dismissal during an effect. Settled measurements wait ten seconds after the animation burst, then collect two 30-second deltas. A second process runs the same fixture with motion disabled through the injected Reduce Motion environment. Native visibility transitions are monitored synchronously throughout each measured interval. Any unexpected state permanently invalidates that interval, even if visibility recovers before the endpoint; settled deltas are checked before being printed. This validation fix has not been profiled again. Existing invalidated evidence and pending energy acceptance remain unchanged.

The fixture-only interval validator has injected-sequence regression coverage (stable, wrong initial/final state, transient occlusion/recovery, transient visibility during hidden sampling, and reset for a new interval):

```bash
mkdir -p .build/motion-visibility-tests
xcrun swiftc -swift-version 6 -parse-as-library scripts/motion-fixture-visibility.swift scripts/test-motion-fixture-visibility.swift -o .build/motion-visibility-tests/check
.build/motion-visibility-tests/check
```

Host: Apple Silicon, macOS 27.0.1 (26A434). No hardware power/GPU counters or whole-app Energy Impact were measured.

### Investigation and retained evidence

An initial 10-second probe with `TimelineView(.animation)` measured 0.006% hidden, 0.104% idle-open, 10.254% animating, but 1.846% after settling. A finite explicit timeline sometimes reached 0.006% settled but residual activity recurred. The longer, cumulative-delta run with explicit timelines recorded:

| Phase | Motion enabled | Motion disabled baseline |
| --- | ---: | ---: |
| Hidden | 0.027% | 0.197% |
| Idle-open before effects | 1.241% | 1.261% |
| Repeated effects | 8.222% | 1.098% |
| Settled, first ~30 seconds | 0.277% | 0.038% |
| Settled, second ~30 seconds | 0.564% | 0.003% |
| Settled, combined ~60 seconds | 0.423% | 0.022% |
| Hidden after effects | 0.238% | 0.010% |

[Raw timeline results](motion-fixture-evidence/timeline-results.txt) and [baseline](motion-fixture-evidence/timeline-baseline-results.txt). These are measurements of the **superseded timeline implementation**, not final acceptance. They do not establish which macOS/SwiftUI activity caused the residual CPU.

The authorized single corrective pass removed the timeline scheduler entirely, replacing it with finite cancellable frame tasks. All 97 tests then passed. Its final profiling attempt recorded:

| Phase | Finite-task implementation |
| --- | ---: |
| Hidden | 0.011% |
| Idle-open | 0.596% |
| Repeated effects | 10.490% |
| Settled, first 31.787 seconds | 0.268% |
| Settled, second 31.980 seconds | 0.056% |

Final idle-open was 0.596%, versus 0.022% in an earlier short probe; this does not establish a matched final settled baseline.

**The final run became occluded during the settled phase and correctly exited with `INVALID: fixture visibility changed during settled`.** The two deltas cannot prove visible settled-idle acceptance; the final hidden-after phase and final motion-disabled baseline were not reached. Do not substitute the earlier baseline or label this final run a pass. [Final raw results](motion-fixture-evidence/finite-task-results.txt), [supplementary ps samples](motion-fixture-evidence/finite-task-ps-samples.txt).

Per supervisor direction, profiling stopped after that corrective pass rather than looping. A valid final 60-second visible settled measurement and matched baseline remain outstanding. Hidden/initial-idle/animated measurements above are evidence, not a claim that all energy acceptance passed.

## Owner real-popup checklist (also include in the delivery review)

Use a correctly configured rebuilt app only when personally ready to replace the running version. Do not reset existing data or add artificial production entries solely to test.

1. On normal future pours/undo, confirm a short rise/fall and settling slosh; the actual ml count stays correct immediately. Overflow droplets stay inside the popup and never block controls. Custom pours, rapid pours and undo still work.
2. Close the popup during a pour or celebration. Reopen after settling, then switch Today → History → Account → Today. Effects must not replay or continue while hidden. Verify this on both Macs when available.
3. On a natural future daily completion, confirm a short silent celebration, once. Undo/recomplete, reopening, relaunch and synced completion must not replay it. Use **isolated fixtures**, not production history edits, for 75-day and historical-correction scenarios.
4. Personally exercise live Reduce Motion when convenient: static water, no slosh/particles, only a subtle completion badge. Check Light/Dark/System and Increase Contrast; no system settings were changed by the worker.
5. Confirm the full-window backing, retained-height edges and native rounded corners remain filled across section changes. Follow [popup-edge checks](popup-edges.md#captains-rebuilt-popup-checklist-include-in-the-pr).
6. Check VoiceOver's actual water amount and requirement states, keyboard focus and control activation during effects. Both actual Macs/scales and actual popup compositing over the desktop remain unverified.
7. Complete the outstanding fixture CPU comparison above, then assess whole-app hidden/idle/animation energy separately from existing network/reminder polling.

No hosted Supabase project, real records, Keychain sessions, legacy identity identifiers, or running user application were touched. No cloud CI is configured.

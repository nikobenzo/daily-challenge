# Phase 3 — read-only widgets evidence

Implementation: `6e507d01f45bd8c0f7e2c0d1132a0cee47126d5a` (foundation `238a45b`) on
`fm/dc-iphone-widgets-p3` (10 October 2026).
This phase adds exactly three stable kinds and five Home Screen families. No interactive
widget actions, Lock Screen families, auth composition or extension networking were added.
`VERSION`, Mac sources/paths, Keychain identifiers and snapshot formats are unchanged.

## Environment and commands

Xcode 27.0 (27A266a); iPhone 17 / iOS 27.0 (24A434). UI captures use the disposable
**Daily Challenge Phase 3** simulator, UDID `C94717B0-D29F-43A8-89C4-EAC7321F4B38`.
Hosted unit/UI apps use synthetic fixtures, temporary roots and fake auth/transports.
No real account, production Keychain, running Mac app, hosted migration or upload was used.
Authorized public `.env.local` was copied without printing it; it remains ignored.

- **A:** `(cd iOS && xcodegen generate)` — generated project and schemes committed with YAML.
- **B:** `swift test` — 185 tests executed; 183 passed. Two unchanged Mac `PopupResizeTests`
  failed three geometry expectations (`panelIsTransparentAndFitsTheGlassWithoutClipping`,
  `panelGrowsBeforeAndShrinksAfterTheAnimatedSheet`). All 62 ChallengeCore and 63
  ChallengeSyncKit tests passed. This is not recorded as a full shared-suite pass; no Mac
  implementation was changed to work around the UI test failures.
- **C:** `xcodebuild test -project iOS/DailyChallenge.xcodeproj -scheme DailyChallenge
  -destination 'platform=iOS Simulator,id=C94717B0-D29F-43A8-89C4-EAC7321F4B38'
  -derivedDataPath .build/ios-test-derived -collect-test-diagnostics never
  -resultBundlePath .build/widget-final-phone.xcresult` — **passed: 25 unit tests (including the 44-image render matrix) and 13 app UI tests; 2 opt-in capture tests skipped**.
- **E:** `bash scripts/ios-archive.sh --check` — **passed**: embedded `.appex`, bundle ID, WidgetKit extension point, matching `0.3.0 (3)` versions, absent extension server configuration and no Sparkle.
- **F:** two bounded SpringBoard placement attempts reached the widget gallery. Try 1
  queried the search result as a button; it is a cell. Try 2 reached the Water gallery but
  failed to match ` Add Widget` (leading space). No widget was placed. Firstmate authorized
  gallery plus production-view rendered snapshots after those two attempts. The capture
  test now matches the suffix for future reproduction; placement was not attempted again.

**Gallery-only verification passed in both appearances:** five pages were traversed and
asserted as Water small/medium, Daily requirements medium, Extras medium/large. Ten actual
SpringBoard gallery PNGs and 44 in-process rendered PNGs are committed. The final captures
include the corrected connected jug outline.

## Capture provenance

All PNGs are under [screenshots/ios/widgets/](screenshots/ios/widgets/).

- `gallery-*.png`: actual simulator SpringBoard widget gallery. Gallery previews deliberately
  use synthetic placeholder data (empty water/pending requirements/no extras), independent
  of any account. They verify extension registration and family presentation, not fixture
  storage access or placed Home Screen behavior.
- `rendered-*.png`: production `WaterWidgetView`, `RequirementsWidgetView`, `ExtrasWidgetView`
  rendered in-process in the iOS unit-test host using SwiftUI `ImageRenderer`. They have an
  explicit token background and 16-point inset, approximate widget dimensions and no system
  Home Screen compositor. They supplement the gallery; they are **not placed Home Screen
  captures** and do not establish WidgetKit scheduling, system margins, tint or link taps.
- **Placed Home Screen screenshots: none.** The original land gate remains outstanding;
  readiness here uses the explicit firstmate fallback, not a claim that F passed.

Rendered matrix, both Light and Dark: water small/medium empty (0), partial (2,250), full
(4,000) and overflow (4,500); requirements medium pending/complete/missed diet; extras
medium/large empty, partial (1/3), ten (1/10), long names and overflow. Large standard size
shows all ten in creation order. Medium retains `Open all 10 extras`; accessibility large
reduces to five rows and keeps that link. Counts and completion come from the same challenge
summaries used by the app; the overflow jug clamps its fill while retaining the actual ml.

## Reproduce the evidence

Create/boot a disposable iPhone 17 with the installed iOS 27 runtime. Do not target a user's
simulator containing a real account. Explicit UDIDs avoid ambiguity with multiple booted devices.

```bash
export WIDGET_SIMULATOR_ID=<disposable-simulator-udid>
# The complete placement procedure (bounded by the caller, no automatic retries):
APPEARANCE=light bash iOS/scripts/capture-widgets.sh
# Authorized fallback: gallery only, no Add Widget action:
WIDGET_CAPTURE_MODE=gallery APPEARANCE=light bash iOS/scripts/capture-widgets.sh
WIDGET_CAPTURE_MODE=gallery APPEARANCE=dark bash iOS/scripts/capture-widgets.sh
```

`WidgetPlacementUITests` launches `-widget-fixture partial`, presses Home, long-presses
wallpaper, taps Edit → Add Widget, searches Daily Challenge, selects its cell and records
XCTest PNG/tree attachments. Placement selects each of the five family pages, Add Widget,
Done. Gallery-only traverses those same pages without placing anything. The helper exports
named PNG attachments and preserves `gallery-` / `home-placed-` prefixes.

For rendered snapshots, run C (or `-only-testing:DailyChallengeTests/WidgetRenderTests`), then:

```bash
xcrun xcresulttool export attachments --path .build/widget-final-phone.xcresult \
  --output-path .build/widget-final-attachments
python3 iOS/scripts/export-widget-attachments.py .build/widget-final-attachments \
  docs/screenshots/ios/widgets
```

## Storage, rollover and limits

Provider tests inject temporary shared roots. Signed-out, no-challenge, missing App Group,
protected/unavailable metadata, corrupt active metadata and corrupt challenge snapshots
produce calm states with no cached titles. Account switch/sign-out hides dormant history.
Preview and placeholder data never read the active account. Corrupt bytes are preserved.

Schedule tests cover Jersey, New York and Sydney spring/fall DST (23/25-hour days), a
challenge zone different from the device zone, pre-start days, overdue provider dates,
water/habit/diet/extra reset, archive visibility, day numbering and streak rollover. Each
entry derives at its own date. Entries cover now plus three calendar midnights; the horizon
requests a reload. WidgetKit can cache content and chooses execution time; this evidence
makes no exact-refresh or remote-sync-without-app-execution promise.

Local app transactions, adoption/sync, foreground reload and sign-out/account changes request
timeline reloads after coordinated metadata is committed. Deep links have fixed destinations
and retain auth/setup gating. Extension-safe builds compile only Theme plus static drawings
and shared storage/service types; no motion timers or existing shared drawing edits.

Owner steps remain: associate the registered group with both App IDs, regenerate/inspect
both profiles and verify signed installation/file protection. Real placed-widget rollover,
locked/unlocked behavior and link taps remain acceptance work; see [TestFlight guidance](ios-testflight.md).

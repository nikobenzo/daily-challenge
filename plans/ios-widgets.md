# iPhone Extras and Widgets

## Decisions (recorded 10 October 2026)

- **D-W1 — diet tap: decided.** The widget flips pending ↔ clean. A day marked missed in the app is never changed from the widget; tapping it opens the app. The app keeps its full cycle and direct state selection. No long-press menu in the widget.
- **D-W2 — Lock Screen: decided.** Version one ships a water-only, read-only accessory-circular ring, marked privacy-sensitive (redacted when the phone is locked). Extras titles and challenge items stay on Home Screen widgets only.
- **D-W3 — review cadence: decided.** Each phase is built, reviewed with screenshots and landed separately before the next starts; five rounds.

Planning only, 10 October 2026. No implementation, entitlement, screenshot, build, account access or upload is delivered by this document. Each phase below is a separate build/review/landing gate, in dependency order. The approved three widgets are the product scope; the two decisions above do not prevent phases 1–3.

## Agreed requirements and current foundation

Deliver iPhone Today/History/Account extras first, then three widgets: water (small and medium), the other four requirements (medium), and extras (medium and large). Use a gallon-style jug silhouette but label the actual goal **4,000 ml / 4 L**: a gallon is not the challenge's unit. Water pours stay 450 ml. Extras remain optional and never affect complete days or streaks. Follow [challenge terminology](../CONTEXT.md), [design tokens](../docs/design-system.md), and [production sync policies](../docs/production-sync.md).

The source at planning time has these boundaries:

| Current file and symbol | Consequence for the build |
| --- | --- |
| `iOS/project.yml`, app target `DailyChallenge` | Minimum iOS is **26**, not 17. Keep that minimum; interactive APIs available from iOS 17 do not require lowering it. The project currently has no extension or App Groups entitlement. Commit regenerated `iOS/DailyChallenge.xcodeproj/project.pbxproj` and scheme changes with target/source changes. |
| `iOS/DailyChallenge/PhoneApp.swift`, `PhoneApp.production()`, `becameActive()`, `backgroundRefresh()` | Production currently constructs `TrackerModel()` with its default directory. Foreground calls `refresh()` and `requestSync()`; background refresh explicitly syncs. Neither is presently a fresh disk reload. |
| `Sources/ChallengeSyncKit/TrackerModel.swift`, `activate(ownerID:)`, `reload()`, `sync(force:)`, private `record(_:)` and `recordExtraSetting(_:)` | A main-actor coordinator serializes one process only. `sync` uploads a captured pending list, awaits networking, then merges into its in-memory store. A second process requires a transaction seam, not just a new path. |
| `Sources/ChallengeCore/ChallengeStore.swift`, `ChallengeStore.init(ownerID:directory:)`, `record`, `merge`, private `commit` | History and pending IDs share one account-scoped version-2 JSON snapshot. Atomic replacement prevents partial JSON; it does not prevent stale-snapshot lost updates. Keep schema, account filenames, challenge/event/device IDs and queue acknowledgment rules. |
| `Sources/ChallengeCore/Challenge.swift`, `Challenge.Action`, `record`, `summary`, `extras(asOf:)`, `DailySummary` | Existing actions cover all interactions; no new wire cases are needed. Undo records a concrete pour ID and returns nil without an active pour. Extras names are trimmed, one line, 1–40 characters; at most 10 active, archive permanent. Definitions are challenge-wide, including historical summaries. |
| `Sources/ChallengeSyncKit/SupabaseChallengeTransport.swift`, `SupabaseChallengeTransport.validate`, `upload`, `fetchEvents` | The app validates session ownership, uploads immutable insert-ignore events and acknowledges only decoded fetched rows. Keep this transport unchanged; the widget will not acquire session tokens. |
| `Sources/ChallengeSyncKit/ChallengeDates.swift`, `ChallengeDates.calendar`; `Sources/ChallengeCore/WaterReminders.swift`, `WaterReminderPlanner.upcoming` | Use calendar intervals in the immutable challenge timezone, including DST, rather than device midnight or adding 86,400 seconds. Notification queues are independent of WidgetKit timelines. |
| `Sources/DailyChallengeProof/ExtrasViews.swift`, `ExtrasSection`, `ExtrasChecklist`, `ExtrasDayPill`, `ExtrasSettingRow`, `ManageExtrasView` | Behaviour reference for iPhone extras, not a Mac file to edit or compile wholesale into the phone. The phone deliberately differs by showing the empty Extras entry point. |
| `iOS/DailyChallenge/TodayScreen.swift`, `TodayScreen`, `PhoneRingRow`, `PhoneWaterSection`; `HistoryScreen.swift`, `HistoryScreen`, `PhoneHabitControls`, `ActivityWords`; `AccountScreen.swift`, `AccountScreen` | Phone owns layout and management presentation. History currently gives extras events generic “Changed” wording. |

No Mac UI, build, paths, Keychain identifiers or store format changes. Shared library changes are allowed only for an opt-in storage seam required by the phone; existing `TrackerModel(directory:clock:)` callers retain their default behaviour. No Live Activities, Apple Watch, extras reordering, backend schema change, widget networking, new background service or public release work. App refresh remains best effort. Public distribution still has the separate account-deletion/privacy requirements documented in [TestFlight guidance](../docs/ios-testflight.md).

## Product and data rules

- **Water:** plus records `.pour(450)` even after reaching the goal. Display uncapped actual ml, clamp the drawn fill at full. Minus records `.undoLatestPour` for today's latest active pour, including custom amounts or synced pours; it never subtracts a fixed 450 or touches yesterday. With none today, disable minus and treat a stale minus invocation as a no-op, with no event or error. This follows existing `Challenge.record` and `TrackerModel.canUndo`.
- **Habits/extras:** tap reverses the currently stored completion through `.setHabit(_:completed:)` or `.setExtra(id:completed:)`. Read state inside the transaction, not from the rendered widget. Archived/unknown extras refuse a new tick and refresh the widget. No corrections or extra management directly in widgets.
- **Diet:** per D-W1, the widget tap toggles pending ↔ clean through `.setDiet` after re-reading current data; a stored missed state is left alone and the tap deep-links into the app. Never infer clean from a tap without re-reading current data.
- **Day:** intent execution time determines today's challenge day. An old entry tapped after midnight acts on the new day, never the displayed yesterday. Show a quiet challenge-date label to make timezone differences intelligible. Day number and streak derive from the challenge, not a synced counter.
- **Account:** show “Open Daily Challenge to sign in” when signed out and “Open Daily Challenge to set up” when signed in without a challenge. Unreadable/protected/unavailable storage gets a calm “Open Daily Challenge” state; do not reset it, scan for another account or expose cached titles. Missing App Group access is an error, never a fallback to a private second store. A locally active signed-in account can log offline; network session expiry is resolved by the app.
- **Extras layout:** show creation order and count, no scrolling inside a widget. Medium shows as many readable rows as fit, then an “Open all N extras” link; large aims to show all 10 at standard size. At large accessibility sizes, reduce visible rows and retain the overflow link. Empty shows “Extras · Add your own to-dos”, opening Manage extras after auth/setup when needed.
- **Sync truth:** success means durably saved locally, not uploaded. Reload timelines after committed edits, foreground reload/sync, setup/adoption and sign-out/account change. No tokens, email, password or service-role key in the group, entries, intent parameters, logs or screenshots. Bind intents to an opaque account generation and challenge ID; refuse stale intents after sign-out or account switching.

## Phase 1 — Extras on iPhone (6–9 hours)

**Build evidence (10 October 2026):** Phase 1 built in commit `d3b6c4ac8f3680ffe2fb03f6eba9e6e0b3688727`; A–D passed (183 shared tests, 9 phone unit tests, 12 UI tests); Light/Dark iPhone 17 / iOS 27.0 simulator captures, including accessibility text size, are committed under `docs/screenshots/ios/`; owner real-sync acceptance still requires confirmation of the existing extras action-kind migration.

**Goal:** make extras usable and correctable on the phone without storage or transport changes.

**In:** Today checklist/count and slim empty entry point; one native Manage extras sheet from Today and Account; add, rename, archive with confirmation, inline cap explanation and validation; History checklist requiring Edit this day; meaningful activity labels for all three extra actions. **Out:** widgets, App Group, rearranging extras, new model semantics or a phone-specific celebration subsystem.

**Files/types:** edit `TodayScreen.swift` (`TodayScreen`), `HistoryScreen.swift` (`HistoryScreen.dayCard`, `ActivityWords.short`/`icon`), `AccountScreen.swift` (`AccountScreen`); add proposed `iOS/DailyChallenge/PhoneExtrasViews.swift` (`PhoneExtrasSection`, `PhoneExtrasChecklist`, `PhoneManageExtrasView`). Call existing `TrackerModel.activeExtras`, `canAddExtra`, `toggleExtra`, `addExtra`, `renameExtra`, `archiveExtra`, `canEdit`; derive counts from `Challenge.DailySummary`. Use `ManageExtrasView` as the archive/title/cap reference. Extend `PhoneFixtures.swift` (`PhoneFixtures`) and existing phone unit/UI suites. Regenerate project via command A below.

**Acceptance:** commands A, B and C below. Fixture tests cover empty entry points, add/rename/archive, 10-active cap, invalid/long titles, historical correction lock and selecting a different day exiting correction mode. Assert extras do not affect `isComplete` or streaks. Update `iPhoneHistoryReadsActionKindsItDoesNotShow` to assert explicit extra wording. Command D captures Light/Dark empty Today, populated Today, Manage extras (including cap), Account entry point and locked/unlocked History under `docs/screenshots/ios/`; no clipped controls at accessibility text size.

**Owner steps:** none to develop; before real sync acceptance, owner confirms the existing extras action-kind migration is deployed as described in production-sync.md. No new migration.

**Risk/mitigation:** importing Mac popovers wholesale gives unsuitable phone sizing; phone-specific sheet uses the same rules and tokens. Archived extras still exist on older days; tests use `extras(asOf:)`, not today's active list for History.

**Land gate:** isolated extras UI works and reviews independently of the remaining phases.

## Phase 2 — Coordinated App Group storage (12–18 hours)

**Build evidence (10 October 2026):** Phase 2 built in commit `34714276c239c8a2e2e5877c82ae33c6465dfd41`; A, B, C and E passed (185 shared tests, 20 phone unit tests and 13 UI tests), with reviewed Light/Dark iPhone 17 / iOS 27.0 Today and storage-recovery simulator captures; [coverage and commands](../docs/ios-widgets-phase2-evidence.md); owner App Group registration/signing and real-device pre-first-unlock protection remain acceptance steps.

**Goal:** app and future extension safely share the durable history/queue, while Mac defaults stay unchanged.

**In:** `group.app.daily-challenge.ios` container resolution, app entitlement, opt-in repository transactions, account visibility metadata, conservative first-launch relocation and recovery tests. **Out:** extension UI, network credentials in the group, changing JSON wire/schema or Mac storage behaviour.

**Files/types:** `PhoneApp.swift` (`production`, `becameActive`, `backgroundRefresh`), `RootView.swift` (account transition presentation), existing `Sources/ChallengeSyncKit/AuthModel.swift` `AuthModel.onSessionChange(_:)` as the immediate lifecycle hook (no auth implementation change); proposed `iOS/Shared/PhoneSharedStore.swift` (`PhoneSharedStore`, `PhoneSharedAccount`) and `iOS/DailyChallenge/DailyChallenge.entitlements`; `iOS/project.yml` and generated project. Add a proposed injected `TrackerStoreAccess` seam in `Sources/ChallengeSyncKit/TrackerModel.swift` or a companion file; route `reload`, setup, local edits, extras edits, imports and post-network `sync` merge through it when supplied. Existing `ChallengeStore` methods remain the transaction engine. Keep `SupabaseChallengeTransport` unchanged. Tests go in `iOS/DailyChallengeTests/` plus kit regression coverage where the seam lives.

**Transaction design:** use a stable group lock file with a process-safe advisory exclusive lock (and same-process serialization), shared by every app/extension accessor. Lock spans fresh `ChallengeStore` load → validation/derive action → record/merge → atomic commit → metadata update. Reads that must agree with active account metadata also take the lock. Never lock an inode that atomic replacement changes, and never hold a lock over network awaits. Sync reads pending under lock, releases for network, then reacquires and loads the latest snapshot before `merge(record:events:)`; only fetched event IDs acknowledge pending entries. Refresh app state from the committed store so widget edits are visible. Preserve setup preflight, conflict errors and account-generation checks before and after awaits.

Publish only an opaque active owner UUID/generation and challenge identity in coordinated metadata after the app has authenticated and opened that account. Wire `AuthModel.onSessionChange(_:)` in `PhoneApp` before `auth.start()`; do not depend solely on SwiftUI `onChange` for account visibility. Clear/invalidate it under the same lock on sign-out/account switch, then request timeline reloads once phase 3 exists. The widget never chooses an owner from untrusted parameters or filename enumeration. A stale action must validate metadata inside the lock. Keep dormant account files isolated for later sign-in; clearing visibility is not deleting history. Choose explicit iOS file protection for shared files (after first unlock) and test the unavailable-before-unlock placeholder; mark personal widget content privacy-sensitive. Do not share Keychain access groups.

**Relocation:** the brief's “no installed users” assumption cannot justify dropping local data: first TestFlight 0.3.0 (3) exists. On first app launch, coordinate an idempotent copy from the old phone-container `TrackerModel.defaultDirectory` into the group. Preserve snapshots, queues, device IDs and relevant recovery/celebration files; keep appearance/reminder preferences device-local. Validate copied stores before publishing the active account; retain originals as recovery until verification. Missing old files is a normal fresh install. If both roots contain differing histories, stop and surface recovery rather than pick a winner or overwrite. Mark completion only after durable validated copy; an interrupted copy retries safely. Never touch the equivalent host Mac directory.

**Acceptance:** A, B, C, E. Temp-root tests with two independent accessors and a separate-process lock test: concurrent pours/ticks, undo, stale app snapshot, sync upload interrupted by widget edits, fetched-ID-only acknowledgment, offline relaunch, account switch/sign-out racing an action, corrupt snapshots, missing entitlement/container, copy interruption, same-content retry and conflicting destination. Assert events and pending IDs survive with identities unchanged; package regression tests preserve default callers. Compare before/after phone fixture summaries. Screenshots: normal Today unchanged and a readable storage-recovery error, never silently empty setup.

**Owner steps:** enable/register the App Group on the team and attach it to the app App ID before signed-device acceptance; phase 3 adds the extension association. Automatic signing may manage provisioning, but an unsigned archive proves neither registration nor entitlement authorization. Use [Apple's App Group configuration](https://developer.apple.com/documentation/xcode/configuring-app-groups) and [manual registration fallback](https://developer.apple.com/help/account/identifiers/register-an-app-group); do not promise that an upload alone creates the group.

**Risk/mitigation:** a wrapper around stale `ChallengeStore` values is still unsafe. Require all opt-in mutations, especially sync merge and extras management, to use fresh-load transactions. Shared library seam is the necessary exception to “phone only”; preserve default Mac call paths and run their existing tests without running the Mac app.

**Land gate:** phone alone runs on the shared store with recovery and concurrency coverage before any extension writes.

## Phase 3 — Three read-only WidgetKit widgets (8–12 hours)

**Build evidence (10 October 2026):** Phase 3 built in commit `6e507d01f45bd8c0f7e2c0d1132a0cee47126d5a`; [commands, simulator gallery and rendered snapshot provenance](../docs/ios-widgets-phase3-evidence.md); firstmate authorized gallery/render fallback after two bounded placement attempts, so actual Home Screen placement remains unverified.

**Goal:** review actual widget layouts and challenge-day rollover before introducing mutations.

**In:** embedded extension `app.daily-challenge.ios.widgets`, three stable widget kinds, static local timeline entries, deep links, placeholders and fixture seeding. Water small/medium, challenge medium, extras medium/large. **Out:** interactive controls (do not draw enabled-looking plus/minus yet), Lock Screen family, extension auth/networking and active jug animation.

**Files/types:** add proposed `iOS/DailyChallengeWidgets/ChallengeWidgets.swift` (`ChallengeWidgets: WidgetBundle`, `WaterWidget`, `RequirementsWidget`, `ExtrasWidget`), `WidgetTimeline.swift` (`ChallengeWidgetEntry`, `ChallengeWidgetProvider`, pure `WidgetDaySchedule`), `WidgetViews.swift` and extension entitlement. Compile `iOS/Shared/PhoneSharedStore.swift` into both targets. Read `ChallengeStore.challenge`, `Challenge.summary(on:asOf:)`, `streaks(asOf:)`, `ChallengeDates.calendar`; do not instantiate `AuthModel` or `PhoneApp.production()` in the extension. Select only needed files from `Sources/DailyChallengeProof/Shared/`: `Theme.swift`, `SharedComponents.swift` for `RingGauge` if extension-safe; use a proposed static `WidgetJugView` rather than `WaterJugView`'s motion clocks. No existing shared drawings need editing.

Edit `iOS/project.yml` to embed an `app-extension` target, restrict it to extension-safe APIs, link `ChallengeCore`/`ChallengeSyncKit` as needed, and share the entitlement. Regenerate committed project/schemes. Update `iOS/scripts/bundle-configuration.sh` or give the extension a version-only phase so both bundle versions come from unchanged `VERSION`, without copying server configuration to a non-networking extension. Extend `scripts/ios-archive.sh --check` to require the embedded `.appex`, its bundle ID, WidgetKit extension point and matching versions, and retain the no-Sparkle check. Add `RootView`/`PhoneApp` routing and timeline reload bridge after committed app changes, adoption/sync and sign-out. Add Debug-only fixture seeding for the shared group; app launch arguments do not reach a separately running extension automatically.

**Timeline contract:** derive each entry at its own date in the saved challenge zone. Supply “now” and precomputed next-midnight entries (including following midnights through a short horizon), then request reload at the horizon. This avoids relying solely on a provider wake exactly at midnight. Zero water, pending habits/diet/extras and recalculated streak/day number appear on the new day; titles follow that day's archive rules. Reload on local changes. WidgetKit controls scheduling and may show cached content; do not promise precise refresh or remote sync without app execution. See [Apple's timeline guidance](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

**Acceptance:** A, B, C, E, then F. Pure schedule tests cover Jersey, New York and Sydney DST boundaries, different device timezone, pre-start date, overdue entries and streak rollover. Provider tests cover signed-out/no-challenge/corrupt/protected states and prevent leaking inactive account data. Simulator fixture gallery lists exactly three kinds and correct sizes. Save placed Home Screen screenshots in both appearances under `docs/screenshots/ios/widgets/`: water empty/partial/full/overflow; requirements pending/complete/missed diet; extras empty/partial/10/long names/overflow. Visible counts and rings agree with the app fixture. Previews supplement but do not replace actual Home Screen captures.

**Owner steps:** associate the same registered group with the extension App ID; regenerate profiles through automatic signing or portal fallback. Check both profiles' group entitlement before a signed installation. No separate App Store Connect app record is needed for the embedded extension. Add these steps to `docs/ios-testflight.md` during implementation.

**Risk/mitigation:** app-only APIs or motion timers can break extension builds or waste resources. Compile a minimal token/drawing set, static fill/rings and extension-safe shared access. Placeholder and snapshot previews must use synthetic data, never a stranger's cached challenge. Deep links use fixed destinations (Today/Manage extras); auth/setup gating remains in `RootView`.

**Land gate:** extension archives embedded correctly and all read-only variants render on an actual simulator Home Screen with tested rollover.

## Phase 4 — App Intents and durable sync hand-off (12–18 hours)

**Goal:** log today's events safely from the widgets while the app is suspended or terminated.

**In:** plus/minus, habit/extra toggles, selected diet rule, transactional validation, timeline reload and foreground/app-refresh sync hand-off. **Out:** direct extension upload, shared auth tokens, custom water input, historical corrections, management intents and background guarantees.

**Files/types:** add proposed `iOS/Shared/WidgetActions.swift` (`WidgetActionRecorder`) and `iOS/DailyChallengeWidgets/WidgetIntents.swift` (`PourWaterIntent`, `UndoWaterIntent`, `ToggleHabitIntent`, `SetDietIntent`, `ToggleExtraIntent`, each `AppIntent.perform()`); update `WidgetViews.swift` with `Button(intent:)`/intent-backed toggles. Give shared actions target membership in phone unit tests without constructing an extension production account. Proposed `WidgetActionRecorder` runs through `PhoneSharedStore` and `ChallengeStore.record`, using existing `.pour`, `.undoLatestPour`, `.setHabit`, `.setDiet`, `.setExtra` exclusively. `TrackerModel.sync(force:)`/`reload` and `PhoneApp.becameActive`/`backgroundRefresh` consume new pending events through the phase-2 seam; no edits to `SupabaseChallengeTransport` required.

Intent parameters carry only supported habit identifiers/extra UUIDs plus opaque generation/challenge identity. Validate all parameters against the active store; no arbitrary owner, date, amount or path. Re-read summary under lock and calculate the action there. Capture execution time once after acquiring access; calculate day in challenge timezone. Do not pass a stale rendered boolean as authoritative state. Successful local commits reload the three kinds, failures preserve prior history and produce a calm recoverable response. An App Intent retry using the same event ID must not add a second event; distinct plus taps must remain distinct. Verify actual system invocation behaviour and use a per-invocation UUID stable within retries, without inventing unsupported exactly-once guarantees.

The extension records to the normal pending queue only. Next app foreground or an iOS-selected refresh reopens latest disk state, uploads through the authenticated transport, merges and acknowledges exact returned IDs. The app also reconciles water reminders after seeing widget edits. A widget reaching 4,000 ml may leave previously queued reminders until the app runs: document this limitation; no new reminder preferences or permission prompts from widgets. Signing out invalidates action metadata before another account is exposed. Existing already-rendered widget images may persist until WidgetKit reloads; privacy-sensitive content and no email reduce exposure, but clearing a cache is not instantaneous.

**Acceptance:** A, B, C, E and F. Inject time, accounts, roots and fake transports; assert every intent records the correct existing action/day/device ID, pending count and concrete undo target. Cover no-pour minus, >4 L plus, synced custom-pour undo, rapid taps, archived extra, forged parameters, corrupt/unavailable storage, stale generation, account switch, midnight between render and tap, concurrent app edits and in-flight sync. End-to-end offline simulator test: terminate the fixture app, tap placed widget, relaunch app and see the entry; fake-server catch-up clears only uploaded/fetched IDs. Check failure does not optimistically show success. Capture water plus/minus, toggled requirements and extras; verify the same values in Today and History.

**Owner steps:** none for the diet rule (D-W1 decided above). No Apple portal change beyond phase 3. Real authenticated sync testing is owner acceptance on a disposable test account, not worker access to the real account.

**Risk/mitigation:** stale state can undo or toggle the wrong data; transactional re-read plus generation checks control local races. Remote concurrent edits retain the existing deterministic timestamp/device/event order, not new conflict semantics. App Intents need not depend on a live SwiftUI observation binding or an app process; the shared action service owns durable writes.

**Land gate:** every action is durable offline and the app's next sync correctly consumes it; read-only placeholders remain safe.

## Phase 5 — Polish, accessibility and owner TestFlight acceptance (7–11 hours)

**Goal:** make the three widgets legible and trustworthy on a real phone and prepare an owner-run release.

**In:** visual polish, VoiceOver, text/contrast/transparency checks, system-tinted widget rendering, the read-only accessory-circular water variant decided in D-W2, documentation and acceptance evidence. **Out:** new widget categories, Lock Screen extras, public App Store launch, uploads by the worker or Mac changes.

**Files/types:** proposed `WidgetViews.swift` (`WidgetJugView`, requirement/extra rows), `WaterWidget.supportedFamilies`, `ChallengeWidgetEntry` privacy handling and `PhoneExtrasViews.swift`; phone fixture/test/screenshot helpers. Use `Theme` light/dark tokens, opaque Reduce Transparency fills and checks/dashes/× alongside colour; check system accent/tinted mode rather than assuming app appearance preferences govern Home Screen widgets. Static jug, no slosh/timer/celebration loops. Water accessibility reads actual ml and goal; plus/minus have distinct labels, habits read requirements/state, extras speak full titles even when visually truncated. Layout must keep tap targets usable within WidgetKit's size budget; overflow opens the app.

Update `HANDOFF.md` (implemented phases versus pending owner acceptance, exact intent rules and App Group path), `docs/ios-testflight.md` (group/profile steps, extension packaging, installed-data relocation, widget/reminder limitations and real-phone checklist), and `README.md` (adding widgets and extras usage). Leave `VERSION` unchanged in worker implementation; owner raises build number only when preparing the next upload, with matching app/extension versions. Do not repeat this guide's older “nothing uploaded yet” text as fact: the task brief reports TestFlight **0.3.0 (3)** already out; owner reconciles release records during release prep.

**Acceptance:** A–F. Capture both appearances for every shipped family, empty/signed-out/setup/error states, all 10 extras, maximum-length titles, large text, Increase Contrast, Reduce Transparency and tinted rendering. Add real Lock Screen fixture capture, the redacted (locked) rendering and the spoken water value. Archive check confirms matching bundles and no accidental credentials/configuration in extension resources. Review screenshots visually, not only file existence; retain explicit captions distinguishing fixtures, actual simulator placement and owner device evidence.

**Owner steps and real-phone gate:** using a disposable account, owner follows updated `docs/ios-testflight.md`, enables/associates the App Group and reviews signed entitlements, increments build number, uploads and updates What to Test. Worker never uploads. After TestFlight install: verify previous phone challenge/queue survived; add all three widgets; log offline with app closed; relaunch and verify sync to another client; undo latest pour and no-pour minus; tick/untick habits/extras and test chosen diet rule; archive from app and refresh widgets; confirm rollover in the challenge timezone; test sign-out/account switch and stale widget tap; verify VoiceOver, locked-device privacy and reminder catch-up. Do not call simulator success real-phone acceptance. Do not modify the captain's real account during automated work.

**Risk/mitigation:** unsigned archives cannot prove Apple authorization, locked-phone behaviour or WidgetKit cadence. Explicit signed/TestFlight checks remain owner gates. Lock Screen variant is small and read-only (D-W2); do not expand it beyond the water ring.

**Land gate:** worker evidence passes and docs list any remaining owner checks honestly. Owner device acceptance closes the release gate separately.

## Verification commands and evidence contract

Run from the repository root, on fixture/test data only. Xcode 27 and iPhone 17/iOS 27 simulator are the intended environment; confirm the selected runtime before captures. For Release checks, use ignored `.env.local` containing only the project's public URL/publishable key (the build worker may copy the authorized local file without printing it). No `.p8`, session tokens or admin keys. Never replace or quit `/Applications/Daily Challenge.app`, read production Keychain or touch host `~/Library/Application Support/DailyChallenge*`.

```bash
# A — regenerate after source/target changes; commit generated project with YAML.
(cd iOS && xcodegen generate)

# B — shared rules and existing default-storage regressions.
swift test

# C — phone unit/UI tests (new widget service/timeline tests join this scheme).
xcodebuild test -project iOS/DailyChallenge.xcodeproj -scheme DailyChallenge \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# D — extend this helper with new phone extras fixtures.
bash iOS/scripts/capture-screenshots.sh

# E — unsigned packaging only; no upload or credentials.
bash scripts/ios-archive.sh --check

# F — after installing a Debug fixture build and placing widgets in the simulator UI.
# Use an isolated test simulator; booted must refer to that simulator.
mkdir -p docs/screenshots/ios/widgets
xcrun simctl ui booted appearance light
xcrun simctl io booted screenshot docs/screenshots/ios/widgets/home-light.png
xcrun simctl ui booted appearance dark
xcrun simctl io booted screenshot docs/screenshots/ios/widgets/home-dark.png
```

The current capture helper installs/launches phone fixtures but does not place widgets. Add a reproducible fixture-seeding and Home Screen placement procedure; do not claim previews or `simctl screenshot` alone prove taps or extension storage. Keep fixture group data synthetic, Debug-only and separately selected from production; temporary directories and account IDs for automated tests. An extension service test bundle or test host may be added if required, but C must actually discover and run its tests, not merely build the target.

Estimated total: **45–68 engineering hours**, plus owner decisions, signing/upload processing and elapsed overnight/real-phone acceptance. Estimates include code, focused tests, review evidence and docs; each gate can land independently and the next begins only after its storage/product dependencies are settled.

## Planning delivery checks

This task changes only this document and links in `HANDOFF.md` and `docs/ios-testflight.md`. Validate Markdown rendering, relative links and cited current symbols; proposed paths/types above are explicitly future additions. Do not run builds, copy configuration, seed fixtures, change `VERSION` or run `swift test` for this documentation-only commit. No implementation has passed the phase gates yet.

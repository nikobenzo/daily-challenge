# Personal Challenge Menu-Bar App

## Status

Agreed product plan from the planning interview, updated to use Supabase instead of CloudKit because the personal Apple Developer membership is inactive. Milestone 1 is in progress: the user applied the proof schema, the native proof app builds, 9 local queue tests, 4 intercepted SDK password-login tests, and local RLS tests pass, and a hosted anonymous read is denied. The user approved switching from email codes to email/password after SMTP/template restrictions blocked OTP. The user's screenshot confirms real password sign-in and a server-confirmed test entry on the first Mac (zero pending, up to date). The user confirmed both Macs are Apple Silicon and work policy permits the app. The user confirmed both Macs run macOS 27.0.1 (26A434), meeting the proof's macOS 14 minimum. Keychain persistence after relaunch, offline recovery, and two-Mac sync/installation still need manual verification. The user explicitly approved moving on while home-Mac testing is unavailable; two-Mac verification is deferred, not passed, and remains required before calling the app fully synced. Milestone 2's local foundation is implemented behind the user-confirmed rules/storage seams, with 21 additional test definitions covering all five requirements, dates, corrections, streaks, and persistence. Milestone 3's functional popup is now wired to that foundation: setup, jug/pours, all four marks, streaks, and explicit calendar corrections. See [interface checks](docs/tracker-interface.md#automated-checks) for current UI coverage. See [production sync](docs/production-sync.md) for implementation and remaining owner acceptance. See [local foundation](docs/local-foundation.md), [interface](docs/tracker-interface.md), and [README.md](README.md). Technical proposals below must be validated; unresolved installation or work-device restrictions must be discussed rather than silently reducing scope.

## Product

A personal native SwiftUI macOS menu-bar app, synced through Supabase between a personal Mac and a work Mac. Both Macs sign into the same app account; their different iCloud accounts are irrelevant to sync. All five daily requirements ship together:

- Water: at least 4,000 ml, normally logged in 450 ml pours.
- Workout: at least 45 minutes, home or gym.
- Walk: at least 45 minutes.
- Diet: self-certified clean, with optional written rules added later.
- Bible reading: at least 10 pages.

No rest-day exemptions. A missed closed day resets the streak. Goal: 75 consecutive complete days, then continue tracking. Days end at midnight in Europe/Jersey. Past corrections and offline use are supported.

## Experience

A large stylized translucent 4-litre jug dominates a compact popup. Plus/minus controls pour or undo water; procedural sloshing and overflow make it playful. Four compact habit icons and a current-streak/75 badge complete the main view. Minimal visible text, native glass styling where supported, accessible labels and Reduce Motion behavior. No Dock icon or normal main window. Water reminders only.

## Detailed plans

- [Domain glossary](CONTEXT.md)
- [Water](plans/water.md)
- [Workout](plans/workout.md)
- [Walk](plans/walk.md)
- [Diet](plans/diet.md)
- [Bible reading](plans/bible-reading.md)
- [Streaks and history](plans/streaks-and-history.md)
- [Interface and animation](plans/interface-and-animation.md)
- [Sync and storage](plans/sync-and-storage.md)
- [Reminders](plans/reminders.md)
- [Setup and distribution](plans/setup-and-distribution.md)

## Build milestones

### 1. Installation, authentication, and two-Mac sync proof

Check supported OS versions, local build/signing options, and work-device restrictions. Create a Supabase project, configure authentication and row-level security, and prove that the same app account can read/write its challenge from both installed apps. Include offline updates, reconnection, relaunch, and unauthorized-access tests.

**Gate:** Sync works securely on the actual two Macs, or the user explicitly approves a revised route. The user has approved proceeding to the local foundation while two-Mac acceptance is deferred; complete that acceptance before declaring production sync ready. No Apple membership purchase or system iCloud change is required for the backend. Installation and notarization limitations remain a separate gate; do not bypass work security policy.

### 2. Local rules, persistence, and tests

Build the date-aware domain model and durable local storage. Implement all five requirements, undo, corrections, and derived streaks. Inject clock/timezone dependencies for deterministic tests. Select a deployment target and persistence implementation after milestone 1.

**Progress:** `ChallengeCore` now provides the rules and versioned, atomic local JSON storage. Tests exercise the two public seams the user confirmed. Caller-supplied clock instants and a fixed Europe/Jersey calendar keep results independent of the device timezone. The proof targets macOS 14+, and both actual Macs run 27.0.1. See [interface, constraints, and tests](docs/local-foundation.md).

**Gate:** Automated tests cover midnight, Jersey DST, missing dates, start-date boundaries, water thresholds, undo, corrections, and streak recalculation; data survives relaunch.

### 3. Functional menu-bar interface and history

**Progress:** Built the native tracker popup with explicit start-date setup, drawn jug and +450 ml/undo/custom pours, all four requirement marks, current/best streaks, milestone count, and monthly history/correction audit. Account diagnostics remain separate; see [production sync status](docs/production-sync.md#scheduling-and-status) for the challenge footer. The build now produces `Daily Challenge.app` 0.2 while preserving the previous bundle/Keychain identity. Automated action/storage and isolated native light/dark layout checks pass; real menu-bar interaction, screen scaling, accessibility, and relaunch acceptance remain manual. See [Account settings usage](README.md#current-state-functional-tracker-with-production-sync) and the [current roadmap](HANDOFF.md#roadmap-and-remaining-acceptance) for implemented settings and remaining work. See [interface details and checks](docs/tracker-interface.md).

Implement setup, the jug and controls, four habit indicators, streak badge, calendar and day editor, settings, launch-at-login option, and sync state. Establish accessible keyboard interaction before visual polish.

**Gate:** A full day can be logged and corrected without needing a developer tool.

### 4. Production sync and reminders

Integrate the proven Supabase authentication/storage route, durable offline queuing, conflict rules, correction history, export/import, and water notifications.

**Gate:** Two-Mac tests show no lost or duplicated pours, stable habit conflict resolution, correct post-sync streaks, and no notification burst on wake.

### 5. Glass styling, animation, accessibility, and acceptance

Polish native glass presentation, jug fill/slosh/spill effects, daily and 75-day celebrations, Reduce Motion, contrast, VoiceOver, and keyboard use. Measure idle and animation resource usage on both Macs.

**Gate:** Real-device acceptance covers offline operation, sleep/wake, midnight, corrections, notifications, backups, and authenticated two-Mac sync. No continuous expensive animation while hidden or idle.

## Out of scope

An iPhone app (future compatible direction only), workout logs, timers, calorie tracking, food enforcement, reading journals, non-water reminders, public sharing, a web app, and a full fluid simulator.

## Definition of done

Both Macs can record the same personal challenge; offline changes reconcile reliably. All five requirements contribute to one accurate streak. Water is visual and quick to log. Closed missed days reset the streak, corrections repair it, and data is exportable. The app feels native and remains usable with animation disabled.

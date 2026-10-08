# Local Challenge Foundation

## Scope

The user confirmed two test seams: challenge rules and durable local storage. `ChallengeCore` implements both without SwiftUI, Supabase, authentication, or a background timer. It now also owns the production event merge and durable queue; see [production sync](production-sync.md) for migration, transport, deployment, and acceptance. Proof messages stay separate.

## Rules interface: Challenge

A value containing one app account's challenge start date and append-only activity history.

- `record(_:on:at:id:)`: pour water, undo the latest active pour, change a habit mark, or change diet state. Dates/clock instants are supplied by the caller. A successful action returns its stable activity ID; undo with no active pour returns nil.
- `summary(on:asOf:)`: active pours, true water total, habit marks, diet state, day status, and that Jersey day's interval.
- `streaks(asOf:)`: current streak, best streak, and currently valid 75-day milestone dates.
- `history(on:)`: read-only activity/correction history for a selected challenge day.

`on` is an instant interpreted in Europe/Jersey, not the device timezone. `at` is the edit time; changing yesterday uses yesterday for `on` and the actual current instant for `at`. Start dates normalize to Jersey midnight. Callers should supply ordinary valid Date instants from setup/the clock.

All five requirements must be met on the same day. Workout, walk, and Bible reading are self-certified booleans; the UI will explain 45 minutes, 45 minutes, and 10 pages respectively. Diet is pending/clean/missed and requires no written rules text. Water uses positive integer millilitres with an exact 4,000 ml threshold; the main UI will supply 450 ml by default.

An unfinished today preserves yesterday's sequence. Only a closed missed day breaks it. Missing dates count as missed without stored failure flags. Corrections recompute current/best streaks and milestone validity. Reaching 75 does not stop or reset tracking; each complete run records its first 75-day crossing.

### Activity history

Actions append history rather than erase earlier records. An undo captures a specific pour ID; repeated application of the same activity ID is idempotent. Reusing an ID with a different day/action/edit time is rejected. To retry, retain the original ID and clock instant, not a newly generated timestamp. Direct legacy `Challenge.record` calls without device metadata retain local order. Production `ChallengeStore` supplies persisted device metadata and stable IDs; merged activities order by client timestamp, device ID, then event ID. Equal-timestamp legacy order is preserved during migration using deterministic legacy origin metadata.

`Challenge.merge` unions immutable activities and validates explicit undo targets instead of replaying undo commands. Independent additions survive; duplicate same-pour undos subtract once. Do not upload serialized challenge snapshots as whole-day replacements.

## Storage interface: ChallengeStore

- Initialize with the authenticated owner ID and a local directory. No saved challenge means setup is needed; malformed/unsupported/wrong-owner data throws, never auto-resets.
- `start(on:)` creates a challenge once. It does not overwrite existing history.
- `record(_:on:at:id:)` applies a validated action to a candidate snapshot, saves atomically, and only then adopts it in memory.
- `challenge` exposes the current rules value for reads; mutation must go through the store to persist.
- `record` (property), `pending`, and `pendingCount` expose immutable settings and durable upload work. `merge(record:events:)` validates owner/identity/content, merges events, and acknowledges only exact server-confirmed rows in one atomic commit.

Example:

```swift
let now = Date()
var store = try ChallengeStore(ownerID: ownerID, directory: dataDirectory)
if store.challenge == nil {
    try store.start(on: selectedStartDate)
}
try store.record(.pour(450), on: now, at: now)
try store.record(.setHabit(.workout, completed: true), on: now, at: now)
try store.record(.setDiet(.clean), on: now, at: now)
let day = store.challenge?.summary(on: now, asOf: now)
let streak = store.challenge?.streaks(asOf: now).current
```

Storage is versioned JSON, with a separate `challenge-<owner-uuid>.json` file per app account. The containing directory is created private; files contain activity, not passwords/tokens. Restoration validates activity IDs, amounts, dates, and undo targets against local rules. Corrupt files are left intact for recovery.

Use **one serialized writer per account per device**. This value-based snapshot store does not coordinate multiple processes or separately loaded writers. The UI keeps one store in its account model. Version 2 adds an atomic outbound queue; opening version 1 first validates it, writes an exclusive timestamped backup, then migrates without restarting the challenge. See [migration details](production-sync.md#local-migration-and-durability). For manual export/import and recovery-copy guidance, see [personal-data backups](../README.md#personal-data-backups).

## Verification

```bash
swift test --filter ChallengeCoreTests
```

Tests (including parameterized cases) cover water threshold/overflow, undo audit history, same-ID retries, all five requirements, reversals, date restrictions, Jersey midnight and both DST transitions, historical gaps/corrections, diet failure timing, milestones beyond 75, complete storage round trips, account separation, corrupt-file rejection, and failure-safe writes. The write-failure test removes write permission from an isolated temporary directory and reopens the last saved state through the public store interface.

## Next step

Production sync is implemented and locally verified. Hosted migration and real two-Mac reconciliation remain owner acceptance steps, not automated-test claims. See [Account settings usage](../README.md#current-state-functional-tracker-with-production-sync) and the [current roadmap and remaining acceptance](../HANDOFF.md#roadmap-and-remaining-acceptance) for implemented settings and remaining work; implemented features and fixture coverage do not imply owner/device acceptance.

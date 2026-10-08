# Production challenge sync

Implementation delivered for owner deployment and two-Mac acceptance. Automated verification is isolated: no hosted migration or real-account acceptance is implied.

## Ownership and transport

`20261008000200_challenge_sync.sql` adds immutable `challenges` (one per Auth owner) and `challenge_events`. Every row is owner-scoped. SELECT/INSERT use RLS; anonymous access and client UPDATE/DELETE are denied. Composite foreign keys and RLS protect challenge children, and the undo foreign key cannot reference another owner's event. Clients cannot set server receipt time. Only the public URL and publishable key belong in the app; sessions retain the existing Keychain identifiers.

`SupabaseChallengeTransport` uses the diagnostic proof's insert-ignore/paginated-read pattern. Parent pours upload before undo batches. Receiving an upload response is **not** acknowledgment: `ChallengeStore.merge` compares immutable IDs and contents before removing matching pending IDs. Conflicting content is an error, never a silent overwrite. The proof remains separate and functional.

Each sync checks Auth ownership, reads the account challenge, inserts missing local settings with conflict-do-nothing, verifies the actual stored settings, uploads pending events, then reads all activity in 500-row pages. Reads are not a transaction across devices: concurrent inserts missed by one pass arrive in the next. No absence is treated as deletion. A failed or incomplete pass leaves local history/pending work intact. SDK session refresh is used before requests; account changes invalidate in-flight UI results and owner-tagged rows cannot be uploaded under another user's RLS identity.

## Merge and settings rules

- Pours merge by stable ID. Totals, completion, streaks, and milestones are derived locally, never authoritative server counters.
- Undo records retain their exact target. Two independent undos of one pour subtract it once and remain in the audit log. Full event history is retained: stale/offline devices cannot resurrect removed activity.
- Explicit habit/diet edits order by **client timestamp, device ID, event ID**, ascending; the last wins. Event IDs generated at identical local timestamps are ordered to retain local edit order. Receipt times never change ordering.
- A receipt/client timestamp difference **strictly greater than five minutes**, in either direction, sets a durable clock warning. Exactly five minutes does not. No edits are quarantined or dropped. The warning says **Clock/delivery delay > 5 min** because offline delivery also creates this difference; it cannot prove a bad clock. Original event timestamps remain intact. The warning remains visible after subsequent successful syncs for this history.
- The current shared challenge setting is its Jersey start date, immutable after setup. Appearance is intentionally device-local; reminders/diet-rule settings and a settings-edit UI are not part of this increment.
- A signed-in device without local history must successfully check the server before setup. It adopts an existing challenge instead of offering setup. Unreachable/missing-schema backends block *new setup*, not logging in an existing local challenge.
- An existing local challenge uploads when the server has none. A unique owner constraint resolves a simultaneous insert race without overwriting either contender. If the local and server challenge identity/settings differ, synchronization stops with an error; the local history, server history, and pending records stay intact. There is no automatic merge/restart or resolution UI. Even identical start dates with different challenge identities are a conflict.

Clock and setup policies were clarified by firstmate for this implementation on 8 October 2026. They resolve the open policy points in the sync/storage plan; they are not evidence of real-device acceptance.

## Local migration and durability

`ChallengeStore` upgrades version 1 to version 2 in the **same account-scoped file**. It first validates the complete legacy snapshot, then creates an exclusive timestamped `challenge-<owner>.json.backup-<UTC timestamp>-<uuid>` copy alongside it. Only after that does it atomically write version 2. Failed backup/write operations throw; corrupt or unsupported files are never reset.

Migration retains start date, activity IDs, amounts, original timestamps, and specific undo targets. Legacy equal-timestamp append order is represented by deterministic `legacy-<ordinal>` origin metadata; new edits use a persisted random device ID. A new challenge identity and all pending IDs are committed together. The captain's start-today/two-450-ml-pour case is covered by a fixture, not by accessing real data. Version-2 reopens retain the identity and queue and do not create another migration backup.

Version 2 stores challenge/settings, full history, per-account device identity, pending IDs, settings acknowledgment, and clock-warning state in one atomic snapshot. Disk writes precede memory changes. Logging never awaits network. Keep one app process/writer per account/device. Do not run an old version against migrated storage; preserve the automatic backup for recovery, and do not manually restore it over newer records.

## Scheduling and status

Sync starts with session activation at app launch, polls every 30 seconds, and is requested on popup foreground, app activation, wake, reconnect, and local edits. Failed attempts back off exponentially (10 seconds initially, up to 15 minutes); automatic triggers respect this deadline. **Sync challenge now** explicitly retries immediately. Relaunch retains pending work and starts a fresh retry schedule.

The footer distinguishes waiting/checking, locally saved pending work, unavailable/error with pending count, and a timestamped successful sync. Pending count includes unacknowledged challenge settings. “Synced” means the last server check succeeded, not that another offline Mac has uploaded its newest work. Diagnostic Pause sync affects test messages only; disconnect the network to test production offline behavior.

## Owner-only hosted deployment

The implementation worker must **not** perform these steps.

1. Keep the same Supabase project and existing Auth user. Do not create a replacement user or delete records. Do not share passwords, session tokens, database credentials, or service-role keys.
2. In the project's SQL Editor, confirm that the already-applied proof migration `20261008000100_sync_probe.sql` exists. Do not rerun it if already applied.
3. Open a **new query** at https://supabase.com/dashboard/project/ujyvvyrugenknhjodfhc/sql/new . Copy the **complete** `supabase/migrations/20261008000200_challenge_sync.sql` and run **once**. It is transactional and deliberately fails if objects already exist. On error, retain the text and arrange diagnosis; do not drop tables, reset the database, or rerun blindly.
4. Expect the new `challenges` and `challenge_events` tables with RLS enabled and no rows initially. The SQL Editor is administrative: its ability to read/write is not a client-policy test. Never run `supabase/tests/*.sql` in the hosted project.
5. Arrange a correctly configured build using the existing public `.env.local`; `swift test` does not package/install the app. Preserve bundle ID, target, Keychain service, and auth storage key. The owner, not an automated test, quits the old app and installs/opens the new build on the first Mac. Never run both versions simultaneously.
6. On the Mac containing the real challenge, use the **same app login**. Check the original start date and 900 ml (plus any later activity) before and after sync. Do not start a new challenge or delete a file. Wait for a successful challenge footer before opening/setup on the other Mac.
7. On the second Mac, sign in to the same app account. It must adopt the original start date/history without setup. Continue with the checklist below.

Without the hosted migration, an existing local challenge keeps accepting local entries and shows a truthful sync error/pending count. A new empty device waits for a working server. This fallback is intentional.

## Two actual Macs: owner acceptance checklist

Both are Apple Silicon, macOS 27.0.1. Installation policy and ad-hoc signing restrictions still apply; do not bypass OS/company controls. Record pass/fail on **each** Mac; automated fixture tests are not completion of these checks.

- [ ] Same login restores after real relaunch; original Jersey start date and all existing entries survive migration. Timestamped pre-migration backup exists. No repeated setup on the second Mac.
- [ ] First Mac's original 900 ml plus subsequent real activity appears identically on both Macs; compare daily audit IDs/history and current/best streaks.
- [ ] Add one distinct pour on each Mac offline. Relaunch while still offline, verify each local addition persists, reconnect, and verify both additions appear once on both Macs.
- [ ] From a shared synchronized pour, disconnect both and undo that same pour on each; reconnect. One subtraction, both correction records, no resurrected pour after a later relaunch.
- [ ] Make conflicting habit/diet edits offline with known times; reconnect. Verify timestamp/device/event ordering yields identical marks/history/streaks. Do not change macOS clock settings just for this check; skew boundaries are covered by fixtures.
- [ ] Correct a historical day and compare recalculated current/best streaks and milestone dates on both Macs.
- [ ] Test foreground, sleep/wake, and reconnect recovery. Check pending/error labels during outage and timestamped synced status afterward.
- [ ] Test expired-session/re-login recovery if available, without deleting local files. Pending work remains attributed to its original account. Local sign-out on one Mac must not sign out the other.
- [ ] If using a separate fixture account for an account-switch check, pending work from the original account must neither appear nor upload under it; switch back and confirm it is retained.
- [ ] Confirm diagnostics still sync only their independent test messages. Production footer, not diagnostic pending count, is the challenge-sync evidence.

Do not manufacture a challenge conflict in the real account. Simultaneous-setup conflicts, response-loss retries, malformed records, account-switch races, skew, and unavailable-backend behavior are exercised with isolated fixtures instead.

## Local verification

```bash
swift test
bash scripts/test-sync-security.sh
```

Swift tests use temporary directories, fixture Auth storage, and intercepted SDK requests only. PostgreSQL uses a disposable private Unix socket with no TCP or hosted credentials. Coverage includes migration backups, duplicate retries, offline convergence, same-pour undo, conflicting edits, clock tolerance, paginated/batched SDK wire format, expired Auth, account switching, relaunch, disk failure, corrupt preservation, and backend failure. No cloud CI is configured; hosted migration and real two-Mac acceptance remain owner steps.

# Sync and Storage

## Agreed requirements and backend change

Use Supabase instead of CloudKit. Both Macs sign into the same personal app account, independent of their system iCloud accounts. Keep native SwiftUI and durable local offline storage. A future iPhone client can use the same backend and app account.

Reason for the change: the user's personal Apple Developer membership is inactive. Supabase avoids CloudKit provisioning; it does not solve macOS signing, notarization, or company installation restrictions.

## First milestone: prove the route

Create a Supabase project and check its current plan limits, inactivity/pausing behavior, and region choices before relying on the free tier. No paid subscription without approval.

Build a minimal native proof using the official Supabase Swift client. Prove sign-in with the same account on both Macs, private authenticated reads/writes, offline additions, reconnect, and relaunch. Agreed sign-in: email and password with a manually provisioned, confirmed Auth user. The user approved this after custom SMTP failed due to an unverified Resend domain and the built-in sender did not permit editing email source. Normal login no longer depends on email delivery, templates, or browser callbacks. Preserve any existing user's identity when setting its password.

References:
- https://supabase.com/docs/reference/swift/introduction
- https://supabase.com/docs/guides/auth
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/api/api-keys

## Proposed implementation boundaries

- A date-aware domain layer derives totals, completion, streaks, and history independently of UI/network access.
- A local repository stores activity and a durable outbound queue.
- A sync coordinator exchanges user-owned records/events with Supabase Postgres through authenticated APIs.
- The UI observes local data and sync status; logging does not wait for a network response.

Production implementation now uses version-2 atomic account-scoped JSON containing full event history and the outbound queue; a timestamped backup precedes legacy migration. See [production implementation, owner deployment and acceptance](../docs/production-sync.md). Supabase is not an automatic offline synchronization engine: reconciliation, retries, and conflict handling are explicit. Realtime, if used, is a refresh signal, not the sole way to recover missed updates. Refresh on launch, foreground/wake, and reconnect.

## Authentication and access control

- Every challenge and related record is owned by a Supabase Auth user.
- Enable row-level security on every client-accessible table. Policies must enforce the authenticated owner for reads, inserts, updates, and deletes, including child-record references.
- Reject anonymous access and attempts by another authenticated user to access this challenge. Test policies before uploading real activity.
- Only project URL and a publishable client key belong in client configuration. A publishable key is not an authorization boundary; RLS is essential.
- Never embed service-role/secret keys or database passwords in the app, repository, exports, or chat.
- Store session credentials using a verified Keychain-backed mechanism; do not assume SDK defaults provide it. Passwords are submitted to Supabase Auth over HTTPS, never stored in configuration/local queues, and cleared from the app's form after an attempt. Initial confirmation is an explicit admin action for this personal account, not an unrestricted client bypass. Password recovery by email remains deferred until SMTP is working.
- Keep account-local caches separated. Sign-out/account changes must not upload one account's pending records under another account.
- Review hosted service privacy and current free-tier limitations. Do not promise Apple-style private iCloud storage or end-to-end encryption.

## Merge rules

- Pours have stable unique IDs. Independent additions merge; retries are idempotent.
- Undo targets a specific pour and preserves correction history; duplicate undo cannot subtract twice.
- Each non-water requirement has explicit edits; latest explicit edit wins.
- Implemented ordering (firstmate clarification, 8 October 2026): retain client event timestamps; order by timestamp, device ID, then event ID. Compare client timestamps with server receipt; strictly beyond a five-minute tolerance in either direction, show a clock/delivery-delay warning. Do not quarantine, drop, or reorder edits by server receipt. Exactly five minutes does not warn. Offline delivery can also trigger this warning; device timestamps cannot guarantee real-world chronological intent.
- Current shared settings are the immutable challenge identity and Jersey start date. An empty signed-in device must check the server before setup and adopt an existing challenge. If unreachable, new setup waits. Existing local challenges upload when the server has none. A differing challenge identity/settings conflict (including a setup race) stops sync and preserves both histories; automatic merging/replacement and a resolution UI are out of scope. Appearance remains device-local. Future editable settings need convergent edit rules, not whole-record replacement.
- Never overwrite an entire day and lose independent water entries.
- Recalculate totals/streaks after merging; a synced streak counter is not authoritative.
- Keep undo/correction records recoverable so missed sync intervals cannot resurrect removed activity. Choose event history or deletion markers deliberately.

## Reliability

Show discreet synced, pending, and error states. Pending work survives relaunch. Handle retry/backoff, expired sessions, sign-in failures, unavailable/paused backend, and network limits without losing entries. An offline device may show stale completion or send a reminder before learning that the other Mac met the goal.

## Export/import

Manual export/import is implemented. See [personal-data backups](../README.md#personal-data-backups) for the supported contents, validation/merge contract, recovery copies, privacy guidance, and remaining acceptance. Cross-account restore requires an explicit future design.

## Acceptance

Test same-account writes on both Macs, anonymous/other-user denial, offline simultaneous additions, duplicate retries, same-pour undo, conflicting habit edits, session expiry, sign-out/account switching, relaunch with pending work, backend failures, corrections, and JSON round trips. Both Macs must converge to identical history and streaks.

# Supabase schemas

The diagnostic proof and production challenge schema are separate. `20261008000100_sync_probe.sql` is the already-deployed diagnostic table. **New:** `20261008000200_challenge_sync.sql` stores owner-protected immutable challenge settings and real activity/undo events.

## Production deployment (owner only)

Follow the [exact hosted migration/install steps and two-Mac checklist](../docs/production-sync.md#owner-only-hosted-deployment). In a new SQL Editor query at https://supabase.com/dashboard/project/ujyvvyrugenknhjodfhc/sql/new, the owner copies the complete `supabase/migrations/20261008000200_challenge_sync.sql` and runs it **once**, after the proof migration. Do not rerun the proof migration, drop tables, or apply test SQL to the hosted project. Stop and report any migration error. Automated workers must never apply migrations or use hosted credentials.

Production SELECT/INSERT policies require the authenticated owner on both tables. Composite foreign keys and RLS protect event children and undo references; client UPDATE/DELETE and receipt-time forgery are denied. The local harness tests both schemas. Existing local tracking remains usable with pending/error status if production tables are not deployed; empty-device setup waits for a successful server check.

The remaining sections describe the retained **diagnostic proof**, not production activity.

## Apply to the hosted project

1. Open https://supabase.com/dashboard/project/ujyvvyrugenknhjodfhc/sql/new (or the project's SQL Editor and a new query).
2. Copy the complete contents of `supabase/migrations/20261008000100_sync_probe.sql`.
3. Paste into the editor and run once.
4. Expect successful execution. The new `public.sync_probe_entries` table has RLS enabled and contains no records.

The migration is transactional. It deliberately fails if the table already exists rather than overwriting data or silently retaining different policies. On an error, report the error text rather than deleting objects or rerunning blindly.

Do not run `supabase/tests/sync_probe_security.sql` in the hosted SQL Editor. It is for the isolated local harness only. The editor normally uses an administrative role; successful queries there do not prove client access is secured.

## Policy behavior

- Anonymous/public-key-only callers cannot read or insert.
- Authenticated users can read and insert only their own entries.
- The native proof app must use the same app user on both Macs.
- Clients cannot update/delete entries. Stable IDs support insert retries without duplicates; retries must use conflict-do-nothing, not update-style upserts.
- The separate production `challenge_events` table provides explicit corrections and targeted undo. This test table does not implement those features.
- Publishable keys are client configuration, not secrets or authorization boundaries. Never use an admin/service-role key in the client.

## Local verification

Run from the repository root:

```bash
bash scripts/test-sync-security.sh
```

Prerequisites: PostgreSQL's `initdb`, `pg_ctl`, and `psql` on PATH. The harness creates a temporary database on a private local Unix socket, applies the actual migration, runs role-based tests, and removes it afterward. No hosted credentials or Docker are needed.

Tests cover both schemas: own-user access, cross-user isolation, forged ownership, challenge-child and undo ownership, anonymous denial, missing identity reads, prohibited update/delete, receipt-time forgery, invalid proof messages, and duplicate insert retries. The local harness supplies a minimal stand-in for Supabase Auth; live JWT validation, email delivery, native session persistence, network retry/reconciliation, and work-Mac installation remain to be tested with the actual app.

## Next gate

The user has applied the hosted migration successfully. A read-only live check confirmed that an anonymous/public-key-only request is denied (HTTP 401, Postgres 42501). Local RLS tests pass. The native proof app is now available; see [build and test instructions](../README.md).

Test real sign-in and private API access before any real habit data is uploaded. The proof now uses a manually confirmed user's email/password login instead of OTP; SMTP/template setup is not required. The user's screenshot confirms real password login and a server-confirmed test entry on the first Mac (zero pending, up to date). Session persistence after relaunch, offline recovery, and two-Mac sync still need manual verification. Confirm work-device policy and OS compatibility before installation; the backend change does not remove signing/notarization restrictions.

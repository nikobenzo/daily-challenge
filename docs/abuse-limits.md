# Abuse limits

The publishable key inside every release is public by design, and sign-ups are open to anyone by the owner's decision. Without limits, one account could store unbounded rows and push the Free plan past its 500 MB database limit, which makes the project read-only and stops sync for everyone. `supabase/migrations/20261009000200_abuse_limits.sql` bounds what any one account can store:

| Limit | Rule |
| --- | --- |
| Event size | `activity` at most 1,024 bytes as stored text. The largest real event, an undo with every key, is about 250 bytes; the longest `deviceID` the schema allows brings it to about 340. |
| Event keys | Only `id`, `day`, `recordedAt`, `action`, `undonePourID` and `deviceID`. |
| Action kind | Exactly one of `pour`, `undoLatestPour`, `setHabit`, `setDiet` (and, after the [extras update](production-sync.md#extras-update-owner-only-once), `defineExtra`, `archiveExtra`, `setExtra`). A malformed row would otherwise be unreadable for that account on every Mac (the app skips such a row and reports it in the sync status). |
| Event dates | `day` and `recordedAt` between 0 and 3.2e9 seconds after 2001-01-01, so 2001 to 2102. |
| Challenge settings | `start_time` between 2020-01-01 and 2100-01-01 (Unix seconds); a year-1 start would hang streak derivation. `time_zone` at most 64 characters; IANA names are at most about 32. |
| Row caps | 10,000 `challenge_events` and 200 `sync_probe_entries` per owner. A 75-day challenge produces a few thousand events at most. |

**Worst case per account: about 14 MB.** Measured on local PostgreSQL 17 with 10,000 events of incompressible padding at the size cap plus 200 full probe rows, including indexes. So about 35 fully used accounts would reach the Free plan's 500 MB. Each account needs its own confirmed email, and the project sends at most 30 emails per hour, so that takes more than an hour of deliberate effort. Watch for it with the [if abuse appears](sign-up-setup.md#if-abuse-appears) runbook.

The caps are a `before insert` trigger, `public.enforce_owner_row_cap`, with a fixed empty `search_path` and no client `EXECUTE` grant. It counts as the inserting user under row-level security, so it sees only that owner's rows, including earlier rows of the same batch insert. Concurrent inserts from two Macs of one account can overshoot a cap by at most the rows in flight.

A client that hits a limit gets an insert error (`23514` for a check, `54000` "row limit reached for this account" for a cap). The app shows a sync error and keeps the events pending locally; nothing is lost. No app change is needed for the migration.

## Owner-only hosted steps

The implementation worker must **not** perform these steps. Apply this migration only after `20261009000100_challenge_time_zone.sql` is in place, as described in [production sync](production-sync.md#timezone-update-owner-only-once). Never run `supabase/tests/*.sql` in the hosted project.

### 1. Calibrate (read-only)

In a new SQL Editor query at https://supabase.com/dashboard/project/ujyvvyrugenknhjodfhc/sql/new, run:

```sql
select owner_id, count(*), max(octet_length(activity::text)) from public.challenge_events group by 1;
select owner_id, count(*) from public.sync_probe_entries group by 1;
```

Expect every maximum under 1,024 and every count well under 10,000 events and 200 probe rows. Then run this read-only check; every count should be `0`:

```sql
select
  count(*) filter (where octet_length(activity::text) > 1024) as oversized,
  count(*) filter (where activity - array['id','day','recordedAt','action','undonePourID','deviceID'] <> '{}'::jsonb) as extra_keys,
  count(*) filter (where not (
    jsonb_array_length(jsonb_path_query_array(activity->'action', '$.keyvalue()')) = 1
    and (activity->'action') - array['pour','undoLatestPour','setHabit','setDiet'] = '{}'::jsonb)) as bad_action,
  count(*) filter (where not (
    (activity->>'day')::float8 between 0 and 3.2e9
    and (activity->>'recordedAt')::float8 between 0 and 3.2e9)) as bad_dates
from public.challenge_events;
select count(*) filter (where not (start_time between 1577836800 and 4102444800)) as bad_start,
  count(*) filter (where char_length(time_zone) > 64) as long_time_zone
from public.challenges;
```

If any count is not `0`, or an account is already above a cap, stop and report the numbers. Do not edit or delete rows to make the migration fit. An account already above a cap would not fail the migration, but it could not add more rows of that kind.

### 2. Apply once

Open a **new query**, copy the **complete** `supabase/migrations/20261009000200_abuse_limits.sql`, and run it **once**. Expect "Success. No rows returned".

The migration is one transaction and checks every existing row. If a row breaks a rule, it stops with an error like the one below and changes nothing:

```text
ERROR:  check constraint "challenge_events_activity_keys" of relation "challenge_events" is violated by some row
```

Running it a second time fails the same way, without changes:

```text
ERROR:  constraint "challenge_events_activity_size" for relation "challenge_events" already exists
```

On any error, keep the text and report it. Do not drop constraints, delete rows or rerun blindly.

### 3. Realtime: turn off public access

The app does not use Realtime. Open **Realtime → Settings** and turn **Allow public access** off, so the publishable key alone cannot use Broadcast or Presence on public channels.

### 4. Security Advisor

Open **Advisors → Security Advisor** and run it. Expect no errors. `enforce_owner_row_cap` (and the sign-up hook, if added) has a fixed `search_path`, so neither should be flagged as mutable. Report any finding instead of following an advisor's fix suggestion blindly.

### 5. Verify (read-only)

```sql
select tablename, rowsecurity from pg_tables where schemaname = 'public';
select * from pg_publication_tables where pubname = 'supabase_realtime';
select grantee, table_name, privilege_type from information_schema.role_table_grants
 where table_schema = 'public' and grantee in ('anon','authenticated') order by 2,1,3;
select proname, prosecdef from pg_proc where pronamespace = 'public'::regnamespace;
select conrelid::regclass, conname, convalidated from pg_constraint
 where conname in ('challenge_events_activity_size','challenge_events_activity_keys',
   'challenge_events_action_kind','challenge_events_dates','challenges_start_sane','challenges_time_zone_length');
select tgrelid::regclass, tgname from pg_trigger where tgname like '%_row_cap';
```

After the [extras update](production-sync.md#extras-update-owner-only-once) the action-kind constraint is named `challenge_events_action_kind_v2`, so that row of the constraint query appears under the new name.

Expected: RLS `true` on all three tables; no publication rows; exactly four grant rows, all for `authenticated`: `SELECT` on the three tables and `INSERT` on `sync_probe_entries` (the challenge tables' `INSERT` grants are column-level and do not appear here), and nothing for `anon`; functions `enforce_owner_row_cap` (plus the sign-up hook, if added), each with `prosecdef` false; six constraints, all `convalidated` true; two row-cap triggers.

Then sync once from a Mac signed in to the real account. The footer should show a successful sync with nothing pending.

## Local verification

```bash
bash scripts/test-sync-security.sh
```

`supabase/tests/abuse_limits.sql` checks that the app's own pour, undo, habit and diet events still insert; that oversized, extra-key, unknown, multiple or empty actions and out-of-range dates are rejected; that a 1,024-byte event is accepted and a 1,025-byte one is not; that year-1 and year-2101 starts and a 65-character time zone are rejected; that the probe cap stops row 201, including inside one batch insert, without affecting another owner; that the event cap accepts row 10,000 and refuses row 10,001; and that clients cannot execute the cap function. The existing RLS suites run against the same schema with the migration applied.

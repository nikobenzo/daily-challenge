-- Abuse limits for a public publishable key: bounded event size and shape,
-- sane challenge settings, and per-account row caps. Apply once, after 20261009000100,
-- following docs/abuse-limits.md. Each constraint validates existing rows, so
-- the whole transaction rolls back if a real row would violate one.
begin;

-- `day` and `recordedAt` are seconds since 2001-01-01 (Swift reference date):
-- 0 to 3.2e9 covers 2001 to 2102. Exactly one known action kind per event.
-- The largest real event (an undo with every key) is about 250 bytes.
alter table public.challenge_events
  add constraint challenge_events_activity_size check (octet_length(activity::text) <= 1024) not valid,
  add constraint challenge_events_activity_keys check (
    (activity - array['id','day','recordedAt','action','undonePourID','deviceID']) = '{}'::jsonb) not valid,
  add constraint challenge_events_action_kind check (
    jsonb_array_length(jsonb_path_query_array(activity->'action', '$.keyvalue()')) = 1
    and ((activity->'action') - array['pour','undoLatestPour','setHabit','setDiet']) = '{}'::jsonb) not valid,
  add constraint challenge_events_dates check (
    (activity->>'day')::float8 between 0 and 3.2e9
    and (activity->>'recordedAt')::float8 between 0 and 3.2e9) not valid;
alter table public.challenge_events validate constraint challenge_events_activity_size;
alter table public.challenge_events validate constraint challenge_events_activity_keys;
alter table public.challenge_events validate constraint challenge_events_action_kind;
alter table public.challenge_events validate constraint challenge_events_dates;

-- `start_time` is Unix seconds: 2020-01-01 to 2100-01-01. IANA zone names are
-- at most about 32 characters.
alter table public.challenges
  add constraint challenges_start_sane check (start_time between 1577836800 and 4102444800) not valid,
  add constraint challenges_time_zone_length check (char_length(time_zone) <= 64) not valid;
alter table public.challenges validate constraint challenges_start_sane;
alter table public.challenges validate constraint challenges_time_zone_length;

-- Runs as the inserting user under RLS, so the count sees only that owner's rows.
create or replace function public.enforce_owner_row_cap() returns trigger
language plpgsql set search_path = '' as $$
declare cap int := tg_argv[0]::int; n bigint;
begin
  execute format('select count(*) from %I.%I where owner_id = $1', tg_table_schema, tg_table_name)
    into n using new.owner_id;
  if n >= cap then
    raise exception 'row limit reached for this account' using errcode = '54000';
  end if;
  return new;
end $$;
revoke all on function public.enforce_owner_row_cap() from public, anon, authenticated;

create trigger challenge_events_row_cap before insert on public.challenge_events
  for each row execute function public.enforce_owner_row_cap('10000');
create trigger sync_probe_entries_row_cap before insert on public.sync_probe_entries
  for each row execute function public.enforce_owner_row_cap('200');

commit;

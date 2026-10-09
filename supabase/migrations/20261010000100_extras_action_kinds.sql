-- Daily checklist extras: allow the three extras action kinds the app writes
-- (defineExtra, archiveExtra, setExtra) next to the original four. Additive only:
-- every other abuse limit, the event size cap, RLS and grants are unchanged.
-- Apply once, after 20261009000200_abuse_limits.sql, and before releasing the build
-- with extras (docs/production-sync.md). Transactional: dropping the old constraint
-- fails, changing nothing, if abuse limits are not applied yet or this already ran.
begin;

alter table public.challenge_events drop constraint challenge_events_action_kind;
alter table public.challenge_events
  add constraint challenge_events_action_kind_v2 check (
    jsonb_array_length(jsonb_path_query_array(activity->'action', '$.keyvalue()')) = 1
    and ((activity->'action') - array['pour','undoLatestPour','setHabit','setDiet',
                                      'defineExtra','archiveExtra','setExtra']) = '{}'::jsonb) not valid;
alter table public.challenge_events validate constraint challenge_events_action_kind_v2;

commit;

-- Custom daily targets and recurring extras: allow the three action kinds that set them
-- (setTarget, setWater, scheduleExtra) next to the seven the app writes, and bound their
-- payloads with the rules every client applies (Challenge.Target, WaterTarget and
-- ExtraSchedule in ChallengeCore and the Android core). Event rows are append-only and
-- clients can never delete them, so a malformed row would stay in the account for ever;
-- the clients skip such a row as unreadable, and these checks keep it out. Each check is
-- at most as strict as the clients, so nothing a client records is refused on upload.
-- A NULL from a missing key must fail, never pass, so each payload rule is coalesced to false.
-- Additive only: size cap, keys, dates, row caps, RLS and grants are unchanged.
-- Apply once, after 20261011000100_account_deletion.sql, and before releasing any build
-- that can write these kinds (docs/production-sync.md). Transactional: dropping the old
-- constraint fails, changing nothing, if 20261010000100 is missing or this already ran.
begin;

alter table public.challenge_events drop constraint challenge_events_action_kind_v2;
alter table public.challenge_events
  add constraint challenge_events_action_kind_v3 check (
    jsonb_array_length(jsonb_path_query_array(activity->'action', '$.keyvalue()')) = 1
    and ((activity->'action') - array['pour','undoLatestPour','setHabit','setDiet',
                                      'defineExtra','archiveExtra','setExtra',
                                      'setTarget','setWater','scheduleExtra']) = '{}'::jsonb) not valid;
alter table public.challenge_events validate constraint challenge_events_action_kind_v3;

-- {"setTarget":{"_0":"walk","name":"Yoga","amount":30,"unit":"minutes","icon":"yoga"}}
-- A slot's label and optional self-certified amount; diet takes a label only. Clients
-- allow 20 characters and at most 80 Unicode scalars; char_length counts the scalars.
alter table public.challenge_events
  add constraint challenge_events_set_target check (
    not (activity->'action' ? 'setTarget') or coalesce((
      jsonb_typeof(activity #> '{action,setTarget}') = 'object'
      and (activity #> '{action,setTarget}') - array['_0','name','amount','unit','icon'] = '{}'::jsonb
      and (activity #>> '{action,setTarget,_0}') in ('workout','walk','diet','bibleReading')
      and jsonb_typeof(activity #> '{action,setTarget,name}') = 'string'
      and char_length(activity #>> '{action,setTarget,name}') between 1 and 80
      and (activity #>> '{action,setTarget,name}') !~ '[[:cntrl:]]|^\s|\s$'
      and (not (activity #> '{action,setTarget}' ? 'icon')
           or (jsonb_typeof(activity #> '{action,setTarget,icon}') = 'string'
               and (activity #>> '{action,setTarget,icon}') ~ '^[a-z]{1,16}$'))
      and case
        when not (activity #> '{action,setTarget}' ?| array['amount','unit']) then true
        when (activity #>> '{action,setTarget,_0}') = 'diet' then false
        when jsonb_typeof(activity #> '{action,setTarget,amount}') <> 'number'
          or (activity #>> '{action,setTarget,amount}') !~ '^[0-9]{1,6}$' then false
        else case activity #>> '{action,setTarget,unit}'
          when 'minutes' then (activity #>> '{action,setTarget,amount}')::int between 5 and 300
          when 'pages' then (activity #>> '{action,setTarget,amount}')::int between 1 and 500
          when 'chapters' then (activity #>> '{action,setTarget,amount}')::int between 1 and 50
          when 'kilometres' then (activity #>> '{action,setTarget,amount}')::int between 1 and 100
          when 'miles' then (activity #>> '{action,setTarget,amount}')::int between 1 and 60
          when 'steps' then (activity #>> '{action,setTarget,amount}')::int between 1000 and 50000
          else false end
      end), false)) not valid;
alter table public.challenge_events validate constraint challenge_events_set_target;

-- {"setWater":{"goal":3000,"pour":250}}: daily goal and the one-tap pour, in ml.
alter table public.challenge_events
  add constraint challenge_events_set_water check (
    not (activity->'action' ? 'setWater') or coalesce((
      jsonb_typeof(activity #> '{action,setWater}') = 'object'
      and (activity #> '{action,setWater}') - array['goal','pour'] = '{}'::jsonb
      and case
        when (activity #>> '{action,setWater,goal}') !~ '^[0-9]{1,5}$'
          or (activity #>> '{action,setWater,pour}') !~ '^[0-9]{1,5}$'
          or jsonb_typeof(activity #> '{action,setWater,goal}') <> 'number'
          or jsonb_typeof(activity #> '{action,setWater,pour}') <> 'number' then false
        else (activity #>> '{action,setWater,goal}')::int between 1000 and 5000
          and (activity #>> '{action,setWater,pour}')::int between 50 and 1000
          and (activity #>> '{action,setWater,pour}')::int <= (activity #>> '{action,setWater,goal}')::int
      end), false)) not valid;
alter table public.challenge_events validate constraint challenge_events_set_water;

-- {"scheduleExtra":{"id":"<UUID>","weekdays":[1,2,3,4,5]}}  ISO weekdays, Monday = 1
-- {"scheduleExtra":{"id":"<UUID>","every":2}}               every N days from its first day
-- {"scheduleExtra":{"id":"<UUID>"}}                          back to a one-off to-do
-- Weekdays must be written as whole numbers (the text form rules out 1.0).
alter table public.challenge_events
  add constraint challenge_events_schedule_extra check (
    not (activity->'action' ? 'scheduleExtra') or coalesce((
      jsonb_typeof(activity #> '{action,scheduleExtra}') = 'object'
      and (activity #> '{action,scheduleExtra}') - array['id','weekdays','every'] = '{}'::jsonb
      and (activity #>> '{action,scheduleExtra,id}')
        ~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
      and not (activity #> '{action,scheduleExtra}' ?& array['weekdays','every'])
      and (not (activity #> '{action,scheduleExtra}' ? 'every')
           or (jsonb_typeof(activity #> '{action,scheduleExtra,every}') = 'number'
               and (activity #>> '{action,scheduleExtra,every}') ~ '^([1-9]|[12][0-9]|30)$'))
      and (not (activity #> '{action,scheduleExtra}' ? 'weekdays')
           or (jsonb_typeof(activity #> '{action,scheduleExtra,weekdays}') = 'array'
               and jsonb_array_length(activity #> '{action,scheduleExtra,weekdays}') between 1 and 7
               and (activity #> '{action,scheduleExtra,weekdays}')::text ~ '^\[[1-7](, [1-7])*\]$'))
    ), false)) not valid;
alter table public.challenge_events validate constraint challenge_events_schedule_extra;

commit;

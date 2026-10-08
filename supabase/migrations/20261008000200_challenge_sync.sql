-- Production append-only challenge settings and activity. Apply once, after
-- 20261008000100. Never run fixture security tests on the hosted project.
begin;

create table public.challenges (
  owner_id uuid primary key references auth.users(id),
  id uuid not null unique,
  start_time double precision not null check (start_time > -62135596800 and start_time < 253402300800),
  unique (owner_id, id)
);

create table public.challenge_events (
  owner_id uuid not null,
  challenge_id uuid not null,
  id uuid not null,
  activity jsonb not null,
  received_at timestamptz not null default now(),
  undone_pour_id uuid generated always as ((activity ->> 'undonePourID')::uuid) stored,
  primary key (owner_id, id),
  unique (owner_id, challenge_id, id),
  foreign key (owner_id, challenge_id) references public.challenges(owner_id, id),
  foreign key (owner_id, challenge_id, undone_pour_id)
    references public.challenge_events(owner_id, challenge_id, id) deferrable initially deferred,
  check (jsonb_typeof(activity) = 'object'),
  check (jsonb_typeof(activity->'id') = 'string' and (activity ->> 'id')::uuid = id),
  check (activity ?& array['id', 'day', 'recordedAt', 'action', 'deviceID']),
  check (jsonb_typeof(activity->'day') = 'number' and jsonb_typeof(activity->'recordedAt') = 'number'),
  check (jsonb_typeof(activity->'action') = 'object'),
  check (jsonb_typeof(activity->'deviceID') = 'string' and length(activity->>'deviceID') between 1 and 128)
);
create index challenge_events_challenge on public.challenge_events(owner_id, challenge_id, id);

alter table public.challenges enable row level security;
alter table public.challenge_events enable row level security;
revoke all on public.challenges, public.challenge_events from public, anon, authenticated;
grant select on public.challenges, public.challenge_events to authenticated;
grant insert (owner_id, id, start_time) on public.challenges to authenticated;
-- Clients cannot forge server receipt times or update/delete correction history.
grant insert (owner_id, challenge_id, id, activity) on public.challenge_events to authenticated;

create policy challenges_read on public.challenges for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy challenges_insert on public.challenges for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy challenge_events_read on public.challenge_events for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy challenge_events_insert on public.challenge_events for insert to authenticated
  with check ((select auth.uid()) = owner_id and exists (
    select 1 from public.challenges c where c.owner_id = challenge_events.owner_id and c.id = challenge_events.challenge_id
  ));

commit;

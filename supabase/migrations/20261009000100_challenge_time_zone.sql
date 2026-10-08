-- Per-challenge timezone: the IANA zone whose midnights bound every challenge
-- day. Apply once, after 20261008000200, before installing the build that
-- carries it. Every existing challenge was created as Jersey days, so existing
-- rows become Europe/Jersey. Transactional; deliberately fails without changes
-- if the column already exists. Never run fixture security tests on the hosted project.
begin;

alter table public.challenges
  add column time_zone text not null default 'Europe/Jersey' check (time_zone <> '');

-- Settings stay immutable: clients may only include the zone when inserting.
-- Table SELECT, row-level policies and the UPDATE/DELETE denial are unchanged.
grant insert (time_zone) on public.challenges to authenticated;

commit;

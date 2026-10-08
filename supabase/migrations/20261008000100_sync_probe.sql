-- First-milestone schema only, not the production habit data model.
-- Apply once through Supabase SQL Editor or the migration tooling.
begin;

create table public.sync_probe_entries (
  id uuid primary key,
  owner_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  message text not null check (char_length(message) between 1 and 200),
  client_created_at timestamptz not null,
  server_created_at timestamptz not null default now()
);

create index sync_probe_entries_owner_created_idx
  on public.sync_probe_entries (owner_id, server_created_at, id);

alter table public.sync_probe_entries enable row level security;
alter table public.sync_probe_entries force row level security;

-- Counteract default table grants. The native app must never use an admin key.
revoke all on table public.sync_probe_entries from public, anon, authenticated;
grant select, insert on table public.sync_probe_entries to authenticated;

create policy sync_probe_entries_read_own
  on public.sync_probe_entries
  for select to authenticated
  using ((select auth.uid()) = owner_id);

create policy sync_probe_entries_insert_own
  on public.sync_probe_entries
  for insert to authenticated
  with check ((select auth.uid()) = owner_id);

comment on table public.sync_probe_entries is
  'Temporary append-only sync proof. Authenticate as the same user on both Macs; no real habit data yet.';

commit;

-- Run only against an isolated local test database, not a hosted project.
-- All fixture records roll back. See scripts/test-sync-security.sh.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', true);

insert into public.sync_probe_entries (id, message, client_created_at)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Mac A offline entry', now());

-- A retry using the same ID is a no-op, not an update or a duplicate.
insert into public.sync_probe_entries (id, message, client_created_at)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Mac A offline entry', now())
on conflict (id) do nothing;

-- A second device authenticated as the same user contributes a distinct entry.
insert into public.sync_probe_entries (id, message, client_created_at)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Mac B offline entry', now());

do $$
begin
  if (select count(*) from public.sync_probe_entries) <> 2 then
    raise exception 'FAIL: same-user entries or retry behavior';
  end if;
  if exists (select 1 from public.sync_probe_entries
    where owner_id <> '11111111-1111-4111-8111-111111111111'::uuid) then
    raise exception 'FAIL: default owner is not authenticated user';
  end if;

  begin
    insert into public.sync_probe_entries (id, owner_id, message, client_created_at)
    values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      '22222222-2222-4222-8222-222222222222', 'Forged owner', now());
    raise exception 'FAIL: cross-owner insert was allowed';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.sync_probe_entries set message = 'Changed';
    raise exception 'FAIL: update was allowed';
  exception when insufficient_privilege then null;
  end;

  begin
    delete from public.sync_probe_entries;
    raise exception 'FAIL: delete was allowed';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.sync_probe_entries (id, message, client_created_at)
    values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '', now());
    raise exception 'FAIL: empty message was allowed';
  exception when check_violation then null;
  end;
end $$;

select set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}', true);

do $$
begin
  if exists (select 1 from public.sync_probe_entries) then
    raise exception 'FAIL: other user can read owner records';
  end if;
end $$;

insert into public.sync_probe_entries (id, message, client_created_at)
values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Other user own record', now());

do $$
begin
  if (select count(*) from public.sync_probe_entries) <> 1 then
    raise exception 'FAIL: other user cannot read their own record';
  end if;
end $$;

-- An authenticated role without a valid user identity cannot see records.
select set_config('request.jwt.claims', '{}', true);

do $$
begin
  if exists (select 1 from public.sync_probe_entries) then
    raise exception 'FAIL: missing identity exposes records';
  end if;
end $$;

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

do $$
begin
  begin
    perform 1 from public.sync_probe_entries;
    raise exception 'FAIL: anonymous read was allowed';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.sync_probe_entries (id, message, client_created_at)
    values ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'Anonymous write', now());
    raise exception 'FAIL: anonymous insert was allowed';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
rollback;
\echo 'PASS: owner access, cross-owner isolation, anonymous denial, append-only permissions, and retry behavior.'

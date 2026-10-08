-- Disposable local harness only. No production identities or credentials.
\set ON_ERROR_STOP on
begin;
-- The challenge that existed before the migration keeps its row and history and
-- becomes Europe/Jersey, the zone every pre-timezone challenge used.
do $$ begin
 if (select time_zone from public.challenges where owner_id = '33333333-3333-4333-8333-333333333333')
    is distinct from 'Europe/Jersey'
    or (select count(*) from public.challenge_events where owner_id = '33333333-3333-4333-8333-333333333333') <> 1 then
  raise exception 'FAIL existing row default';
 end if;
 -- RLS and grants are unchanged apart from inserting the new column.
 if not (select relrowsecurity from pg_class where oid = 'public.challenges'::regclass)
    or (select array_agg(policyname::text order by policyname) from pg_policies
        where schemaname = 'public' and tablename = 'challenges') <> array['challenges_insert', 'challenges_read']
    or not has_column_privilege('authenticated', 'public.challenges', 'time_zone', 'INSERT')
    or not has_column_privilege('authenticated', 'public.challenges', 'time_zone', 'SELECT')
    or has_column_privilege('authenticated', 'public.challenges', 'time_zone', 'UPDATE')
    or has_table_privilege('authenticated', 'public.challenges', 'UPDATE')
    or has_table_privilege('authenticated', 'public.challenges', 'DELETE')
    or has_column_privilege('anon', 'public.challenges', 'time_zone', 'SELECT')
    or has_column_privilege('anon', 'public.challenges', 'time_zone', 'INSERT') then
  raise exception 'FAIL privileges or policies changed';
 end if;
end $$;
insert into auth.users(id) values
 ('11111111-1111-4111-8111-111111111111'), ('22222222-2222-4222-8222-222222222222');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111"}', true);
insert into public.challenges(owner_id,id,start_time,time_zone) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',1791460800,'Australia/Sydney');
-- An insert retry of the same settings is ignored, never an update.
insert into public.challenges(owner_id,id,start_time,time_zone) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',1791460800,'Europe/London')
 on conflict(owner_id) do nothing;
do $$ begin
 if (select array_agg(time_zone) from public.challenges) <> array['Australia/Sydney'] then
  raise exception 'FAIL owner zone read/insert/retry or cross-user read';
 end if;
 begin
  update public.challenges set time_zone = 'Europe/London';
  raise exception 'FAIL zone update';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.challenges(owner_id,id,start_time,time_zone) values
   ('22222222-2222-4222-8222-222222222222',gen_random_uuid(),1791414000,'Europe/Jersey');
  raise exception 'FAIL forged owner with zone';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222"}', true);
do $$ begin
 begin
  insert into public.challenges(owner_id,id,start_time,time_zone) values
   ('22222222-2222-4222-8222-222222222222',gen_random_uuid(),1791414000,'');
  raise exception 'FAIL empty zone';
 exception when check_violation then null; end;
 begin
  insert into public.challenges(owner_id,id,start_time,time_zone) values
   ('22222222-2222-4222-8222-222222222222',gen_random_uuid(),1791414000,null);
  raise exception 'FAIL null zone';
 exception when not_null_violation then null; end;
end $$;
-- An app that predates this column omits it and still gets the Jersey default.
insert into public.challenges(owner_id,id,start_time) values
 ('22222222-2222-4222-8222-222222222222','dddddddd-dddd-4ddd-8ddd-dddddddddddd',1791414000);
do $$ begin
 if (select array_agg(time_zone) from public.challenges) <> array['Europe/Jersey'] then
  raise exception 'FAIL omitted zone default or cross-user read';
 end if;
end $$;
set local role anon;
do $$ begin
 begin perform time_zone from public.challenges; raise exception 'FAIL anon zone read';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
\echo 'PASS: timezone default for existing rows, owner-only zone insert/read, immutable zone, unchanged RLS and anonymous denial.'

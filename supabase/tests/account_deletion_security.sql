-- Disposable local harness only. No production identities or credentials.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values
 ('11111111-1111-4111-8111-111111111111'), ('22222222-2222-4222-8222-222222222222');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111"}', true);
insert into public.challenges(owner_id,id,start_time) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',1791414000);
insert into public.challenge_events(owner_id,challenge_id,id,activity) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"pour":{"_0":450}}}'),
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  '{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","day":813369600,"recordedAt":813412900,"deviceID":"MacA","undonePourID":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","action":{"undoLatestPour":{}}}');
insert into public.sync_probe_entries(id,message,client_created_at) values
 ('abababab-abab-4bab-8bab-abababababab','hello',now());
select set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222"}', true);
insert into public.challenges(owner_id,id,start_time) values
 ('22222222-2222-4222-8222-222222222222','dddddddd-dddd-4ddd-8ddd-dddddddddddd',1791414000);
insert into public.challenge_events(owner_id,challenge_id,id,activity) values
 ('22222222-2222-4222-8222-222222222222','dddddddd-dddd-4ddd-8ddd-dddddddddddd','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  '{"id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","day":813369600,"recordedAt":813412800,"deviceID":"Phone","action":{"pour":{"_0":450}}}');
insert into public.sync_probe_entries(id,message,client_created_at) values
 ('cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd','hello',now());

-- Anonymous (publishable key only) callers cannot run it at all.
reset role;
set local role anon;
select set_config('request.jwt.claims', '', true);
do $$ begin
 begin
   perform public.delete_own_account();
   raise exception 'FAIL anonymous deletion';
 exception when insufficient_privilege then null; end;
end $$;

-- An authenticated role without a user identity deletes nothing.
reset role;
set local role authenticated;
do $$ begin
 begin
   perform public.delete_own_account();
   raise exception 'FAIL deletion without identity';
 exception when insufficient_privilege then null; end;
end $$;

-- Clients still cannot delete rows themselves, and nobody can name another account.
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111"}', true);
do $$ begin
 begin
   delete from public.challenges;
   raise exception 'FAIL direct challenge delete';
 exception when insufficient_privilege then null; end;
 begin
   delete from auth.users;
   raise exception 'FAIL direct auth delete';
 exception when insufficient_privilege then null; end;
 if exists(select from pg_proc where proname = 'delete_own_account' and pronargs <> 0) then
   raise exception 'FAIL deletion takes an account argument';
 end if;
end $$;

-- User 1 deletes themselves; a second call (a retry after a lost response) is a no-op.
select public.delete_own_account();
select public.delete_own_account();
-- Their still-valid session cannot recreate data for the deleted account.
do $$ begin
 begin
   insert into public.challenges(owner_id,id,start_time) values
    ('11111111-1111-4111-8111-111111111111','abababab-0000-4000-8000-abababababab',1791414000);
   raise exception 'FAIL recreated deleted account data';
 exception when foreign_key_violation then null; end;
end $$;

-- The pre-existing account (seeded before the migration, with a pour and its undo) too.
select set_config('request.jwt.claims', '{"sub":"5eed0000-0000-4000-8000-000000000001"}', true);
select public.delete_own_account();

reset role;
-- The deferred undo foreign key must hold once every cascade has run.
set constraints all immediate;
do $$ begin
 if exists(select from auth.users where id in ('11111111-1111-4111-8111-111111111111', '5eed0000-0000-4000-8000-000000000001'))
    or exists(select from public.challenges where owner_id in ('11111111-1111-4111-8111-111111111111', '5eed0000-0000-4000-8000-000000000001'))
    or exists(select from public.challenge_events where owner_id in ('11111111-1111-4111-8111-111111111111', '5eed0000-0000-4000-8000-000000000001'))
    or exists(select from public.sync_probe_entries where owner_id = '11111111-1111-4111-8111-111111111111') then
   raise exception 'FAIL deleted account rows remain';
 end if;
 -- Every other account is untouched.
 if not exists(select from auth.users where id = '22222222-2222-4222-8222-222222222222')
    or (select count(*) from public.challenges where owner_id = '22222222-2222-4222-8222-222222222222') <> 1
    or (select count(*) from public.challenge_events where owner_id = '22222222-2222-4222-8222-222222222222') <> 1
    or (select count(*) from public.sync_probe_entries where owner_id = '22222222-2222-4222-8222-222222222222') <> 1
    or (select count(*) from public.challenges where owner_id = '33333333-3333-4333-8333-333333333333') <> 1
    or (select count(*) from public.challenge_events where owner_id = '33333333-3333-4333-8333-333333333333') <> 1 then
   raise exception 'FAIL another account changed';
 end if;
 -- Only authenticated sessions may execute it; table privileges and policies are unchanged.
 if has_function_privilege('anon', 'public.delete_own_account()', 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.delete_own_account()', 'EXECUTE')
    or not (select prosecdef from pg_proc where oid = 'public.delete_own_account()'::regprocedure)
    or has_table_privilege('authenticated', 'public.challenges', 'DELETE')
    or has_table_privilege('authenticated', 'public.challenge_events', 'DELETE')
    or has_table_privilege('authenticated', 'public.challenges', 'UPDATE')
    or (select count(*) from pg_policies where schemaname = 'public' and tablename in ('challenges', 'challenge_events')) <> 4 then
   raise exception 'FAIL privileges or policies changed';
 end if;
end $$;
\echo 'PASS: own-account deletion with cascades (including a pre-existing pour and undo), idempotent retry, anonymous and identity-less denial, other accounts untouched, unchanged table privileges.'
rollback;

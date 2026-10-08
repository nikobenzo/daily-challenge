-- Disposable local harness only. No production identities or credentials.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values
 ('11111111-1111-4111-8111-111111111111'), ('22222222-2222-4222-8222-222222222222');
do $$ begin
 if has_function_privilege('authenticated', 'public.enforce_owner_row_cap()', 'execute')
   or has_function_privilege('anon', 'public.enforce_owner_row_cap()', 'execute') then
   raise exception 'FAIL row cap function executable by clients';
 end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111"}', true);
insert into public.challenges(owner_id,id,start_time,time_zone) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',1791414000,'America/Argentina/ComodRivadavia');
-- Every action kind the app writes, in its exact encoding, still inserts.
insert into public.challenge_events(owner_id,challenge_id,id,activity) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','b0000000-0000-4000-8000-000000000001',
  '{"id":"b0000000-0000-4000-8000-000000000001","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"pour":{"_0":450}}}'),
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','b0000000-0000-4000-8000-000000000002',
  '{"id":"b0000000-0000-4000-8000-000000000002","day":813369600,"recordedAt":813412900,"deviceID":"MacA","action":{"undoLatestPour":{}},"undonePourID":"b0000000-0000-4000-8000-000000000001"}'),
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','b0000000-0000-4000-8000-000000000003',
  '{"id":"b0000000-0000-4000-8000-000000000003","day":813369600,"recordedAt":813413000,"deviceID":"MacA","action":{"setHabit":{"_0":"bibleReading","completed":true}}}'),
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','b0000000-0000-4000-8000-000000000004',
  '{"id":"b0000000-0000-4000-8000-000000000004","day":813369600,"recordedAt":813413100,"deviceID":"MacA","action":{"setDiet":{"_0":"clean"}}}');
do $$
declare
 base jsonb := '{"id":"c0000000-0000-4000-8000-000000000001","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"setDiet":{"_0":""}}}';
 pad int := 1024 - octet_length(base::text);
 bad jsonb;
begin
 if (select count(*) from public.challenge_events) <> 4 then
   raise exception 'FAIL normal pour, undo, habit and diet events';
 end if;
 -- Exactly 1024 bytes is accepted; one more byte is rejected.
 insert into public.challenge_events(owner_id,challenge_id,id,activity) values
  ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','c0000000-0000-4000-8000-000000000001',
   jsonb_set(base, '{action,setDiet,_0}', to_jsonb(repeat('x', pad))));
 begin
  insert into public.challenge_events(owner_id,challenge_id,id,activity) values
   ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','c0000000-0000-4000-8000-000000000002',
    jsonb_set(jsonb_set(base, '{id}', '"c0000000-0000-4000-8000-000000000002"'), '{action,setDiet,_0}', to_jsonb(repeat('x', pad + 1))));
  raise exception 'FAIL oversized event';
 exception when check_violation then null; end;
 foreach bad in array array[
  -- extra top-level key
  '{"id":"c0000000-0000-4000-8000-000000000003","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"pour":{"_0":450}},"extra":1}',
  -- unknown action
  '{"id":"c0000000-0000-4000-8000-000000000003","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"notARealAction":true}}',
  -- two action kinds
  '{"id":"c0000000-0000-4000-8000-000000000003","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"pour":{"_0":450},"setDiet":{"_0":"clean"}}}',
  -- no action kind
  '{"id":"c0000000-0000-4000-8000-000000000003","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{}}',
  -- day out of range
  '{"id":"c0000000-0000-4000-8000-000000000003","day":1e300,"recordedAt":813412800,"deviceID":"MacA","action":{"pour":{"_0":450}}}',
  -- recordedAt before 2001
  '{"id":"c0000000-0000-4000-8000-000000000003","day":813369600,"recordedAt":-1,"deviceID":"MacA","action":{"pour":{"_0":450}}}'
 ]::jsonb[] loop
  begin
   insert into public.challenge_events(owner_id,challenge_id,id,activity) values
    ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','c0000000-0000-4000-8000-000000000003',bad);
   raise exception 'FAIL malformed event accepted: %', bad;
  exception when check_violation then null; end;
 end loop;
end $$;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222"}', true);
do $$ begin
 -- Year 1 and year 2101 starts and oversized time zones are rejected.
 begin
  insert into public.challenges(owner_id,id,start_time) values
   ('22222222-2222-4222-8222-222222222222','dddddddd-dddd-4ddd-8ddd-dddddddddddd',-62135596000);
  raise exception 'FAIL year-1 start';
 exception when check_violation then null; end;
 begin
  insert into public.challenges(owner_id,id,start_time) values
   ('22222222-2222-4222-8222-222222222222','dddddddd-dddd-4ddd-8ddd-dddddddddddd',4133980800);
  raise exception 'FAIL year-2101 start';
 exception when check_violation then null; end;
 begin
  insert into public.challenges(owner_id,id,start_time,time_zone) values
   ('22222222-2222-4222-8222-222222222222','dddddddd-dddd-4ddd-8ddd-dddddddddddd',1791414000,repeat('x',65));
  raise exception 'FAIL oversized time zone';
 exception when check_violation then null; end;
end $$;
-- Probe cap: 200 rows per owner, then a clean refusal; other owners are unaffected.
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111"}', true);
insert into public.sync_probe_entries(id,message,client_created_at)
 select gen_random_uuid(),'probe',now() from generate_series(1,200);
do $$ begin
 begin
  insert into public.sync_probe_entries(id,message,client_created_at) values (gen_random_uuid(),'probe',now());
  raise exception 'FAIL probe row 201';
 exception when program_limit_exceeded then null; end;
end $$;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222"}', true);
insert into public.sync_probe_entries(id,message,client_created_at) values (gen_random_uuid(),'probe',now());
-- One batch statement cannot overshoot the cap: the trigger sees earlier rows of the same statement.
do $$ begin
 begin
  insert into public.sync_probe_entries(id,message,client_created_at)
   select gen_random_uuid(),'probe',now() from generate_series(1,200);
  raise exception 'FAIL batch past probe cap';
 exception when program_limit_exceeded then null; end;
 if (select count(*) from public.sync_probe_entries) <> 1 then
  raise exception 'FAIL batch partially applied';
 end if;
end $$;
-- Event cap: fill owner 1 to 9,999 rows without per-row triggers, then row
-- 10,000 is accepted and row 10,001 is refused.
reset role;
set local session_replication_role = replica;
insert into public.challenge_events(owner_id,challenge_id,id,activity)
 select '11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',u,
  jsonb_build_object('id',u,'day',813369600,'recordedAt',813412800,'deviceID','Fill','action','{"pour":{"_0":1}}'::jsonb)
 from (select gen_random_uuid() u from generate_series(1, 9999 - (
  select count(*) from public.challenge_events where owner_id='11111111-1111-4111-8111-111111111111')::int)) g;
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111"}', true);
insert into public.challenge_events(owner_id,challenge_id,id,activity) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','e0000000-0000-4000-8000-000000000001',
  '{"id":"e0000000-0000-4000-8000-000000000001","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"pour":{"_0":450}}}');
do $$ begin
 if (select count(*) from public.challenge_events) <> 10000 then
   raise exception 'FAIL event row 10000';
 end if;
 begin
  insert into public.challenge_events(owner_id,challenge_id,id,activity) values
   ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','e0000000-0000-4000-8000-000000000002',
    '{"id":"e0000000-0000-4000-8000-000000000002","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"pour":{"_0":450}}}');
  raise exception 'FAIL event row 10001';
 exception when program_limit_exceeded then null; end;
end $$;
reset role;
rollback;
\echo 'PASS: event size and shape limits, sane dates, per-owner row caps, and normal pour/undo/habit/diet events.'

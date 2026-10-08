-- Disposable local harness only. No production identities or credentials.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values
 ('11111111-1111-4111-8111-111111111111'), ('22222222-2222-4222-8222-222222222222');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111"}', true);
insert into public.challenges(owner_id,id,start_time) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',1791414000);
insert into public.challenges(owner_id,id,start_time) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',1791414000)
 on conflict(owner_id) do nothing;
insert into public.challenge_events(owner_id,challenge_id,id,activity) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 '{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"pour":{"_0":450}}}');
insert into public.challenge_events(owner_id,challenge_id,id,activity)
 select owner_id,challenge_id,id,activity from public.challenge_events on conflict(owner_id,id) do nothing;
do $$
begin
 if (select count(*) from public.challenges) <> 1 or (select count(*) from public.challenge_events) <> 1 then
   raise exception 'FAIL owner read/insert/retry';
 end if;
 begin
   insert into public.challenges(owner_id,id,start_time) values
    ('22222222-2222-4222-8222-222222222222',gen_random_uuid(),1791414000);
   raise exception 'FAIL forged challenge owner';
 exception when insufficient_privilege then null; end;
 begin
   insert into public.challenge_events(owner_id,challenge_id,id,activity,received_at)
    select owner_id,challenge_id,id,activity,now() from public.challenge_events;
   raise exception 'FAIL forged receipt time';
 exception when insufficient_privilege then null; end;
 begin
   update public.challenges set start_time=0;
   raise exception 'FAIL challenge update';
 exception when insufficient_privilege then null; end;
 begin
   delete from public.challenges;
   raise exception 'FAIL challenge delete';
 exception when insufficient_privilege then null; end;
 begin
   update public.challenge_events set activity='{}';
   raise exception 'FAIL event update';
 exception when insufficient_privilege then null; end;
 begin
   delete from public.challenge_events;
   raise exception 'FAIL event delete';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222"}', true);
do $$
begin
 if exists(select from public.challenges) or exists(select from public.challenge_events) then
   raise exception 'FAIL cross-user read';
 end if;
 -- Owner is valid but the parent belongs to another user: child protection.
 begin
   insert into public.challenge_events(owner_id,challenge_id,id,activity) values
    ('22222222-2222-4222-8222-222222222222','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','cccccccc-cccc-4ccc-8ccc-cccccccccccc',
     '{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","day":813369600,"recordedAt":813412800,"deviceID":"MacB","action":{"pour":{"_0":450}}}');
   raise exception 'FAIL cross-owner child reference';
 exception when insufficient_privilege then null; end;
 begin
   insert into public.challenge_events(owner_id,challenge_id,id,activity) values
    ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','cccccccc-cccc-4ccc-8ccc-cccccccccccc',
     '{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","day":813369600,"recordedAt":813412800,"deviceID":"MacB","action":{"pour":{"_0":450}}}');
   raise exception 'FAIL forged child owner';
 exception when insufficient_privilege then null; end;
end $$;
insert into public.challenges(owner_id,id,start_time) values
 ('22222222-2222-4222-8222-222222222222','dddddddd-dddd-4ddd-8ddd-dddddddddddd',1791414000);
insert into public.challenge_events(owner_id,challenge_id,id,activity) values
 ('22222222-2222-4222-8222-222222222222','dddddddd-dddd-4ddd-8ddd-dddddddddddd','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  '{"id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","day":813369600,"recordedAt":813412800,"deviceID":"MacB","action":{"pour":{"_0":450}}}');
do $$ begin
 if (select count(*) from public.challenges) <> 1 or (select count(*) from public.challenge_events) <> 1 then
  raise exception 'FAIL second user own data';
 end if;
end $$;
set constraints all immediate;
do $$ begin
 begin
  insert into public.challenge_events(owner_id,challenge_id,id,activity) values
   ('22222222-2222-4222-8222-222222222222','dddddddd-dddd-4ddd-8ddd-dddddddddddd','ffffffff-ffff-4fff-8fff-ffffffffffff',
    '{"id":"ffffffff-ffff-4fff-8fff-ffffffffffff","day":813369600,"recordedAt":813412800,"deviceID":"MacB","action":{"undoLatestPour":{}},"undonePourID":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}');
  raise exception 'FAIL undo references another owner pour';
 exception when foreign_key_violation then null; end;
end $$;
-- An own-account undo preserves its audit record and references its own pour.
insert into public.challenge_events(owner_id,challenge_id,id,activity) values
 ('22222222-2222-4222-8222-222222222222','dddddddd-dddd-4ddd-8ddd-dddddddddddd','ffffffff-ffff-4fff-8fff-ffffffffffff',
  '{"id":"ffffffff-ffff-4fff-8fff-ffffffffffff","day":813369600,"recordedAt":813412800,"deviceID":"MacB","action":{"undoLatestPour":{}},"undonePourID":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}');
select set_config('request.jwt.claims', '{}', true);
do $$ begin
 if exists(select from public.challenges) or exists(select from public.challenge_events) then
  raise exception 'FAIL missing identity read';
 end if;
 begin
  insert into public.challenges(owner_id,id,start_time) values
   ('11111111-1111-4111-8111-111111111111',gen_random_uuid(),1791414000);
  raise exception 'FAIL missing identity insert';
 exception when insufficient_privilege then null; end;
end $$;
set local role anon;
do $$
begin
 begin perform 1 from public.challenges; raise exception 'FAIL anon challenge read';
 exception when insufficient_privilege then null; end;
 begin perform 1 from public.challenge_events; raise exception 'FAIL anon event read';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.challenges(owner_id,id,start_time) values
   ('11111111-1111-4111-8111-111111111111',gen_random_uuid(),1791414000);
  raise exception 'FAIL anon challenge insert';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.challenge_events(owner_id,challenge_id,id,activity) values
   ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',gen_random_uuid(),'{}');
  raise exception 'FAIL anon event insert';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
\echo 'PASS: production owners, child ownership, anonymous denial, immutable settings/events, server receipts, idempotent retries.'

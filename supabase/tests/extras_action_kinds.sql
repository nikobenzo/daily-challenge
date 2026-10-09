-- Disposable local harness only. No production identities or credentials.
-- After 20261010000100_extras_action_kinds.sql: the extras events the app writes, in
-- their exact encoding, insert; unknown, multiple and empty actions are still rejected.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values ('44444444-4444-4444-8444-444444444444');
do $$ begin
 if exists (select 1 from pg_constraint where conname = 'challenge_events_action_kind') then
   raise exception 'FAIL the original action-kind constraint must be replaced';
 end if;
 if not exists (select 1 from pg_constraint where conname = 'challenge_events_action_kind_v2' and convalidated) then
   raise exception 'FAIL the widened action-kind constraint must exist and be validated';
 end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-8444-444444444444"}', true);
insert into public.challenges(owner_id,id,start_time,time_zone) values
 ('44444444-4444-4444-8444-444444444444','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',1791414000,'Europe/Jersey');
insert into public.challenge_events(owner_id,challenge_id,id,activity) values
 ('44444444-4444-4444-8444-444444444444','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','e0000000-0000-4000-8000-000000000001',
  '{"id":"e0000000-0000-4000-8000-000000000001","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"defineExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","title":"Stretch for ten minutes"}}}'),
 ('44444444-4444-4444-8444-444444444444','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','e0000000-0000-4000-8000-000000000002',
  '{"id":"e0000000-0000-4000-8000-000000000002","day":813369600,"recordedAt":813412900,"deviceID":"MacA","action":{"setExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","completed":true}}}'),
 ('44444444-4444-4444-8444-444444444444','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','e0000000-0000-4000-8000-000000000003',
  '{"id":"e0000000-0000-4000-8000-000000000003","day":813369600,"recordedAt":813413000,"deviceID":"MacA","action":{"archiveExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001"}}}'),
 ('44444444-4444-4444-8444-444444444444','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','e0000000-0000-4000-8000-000000000004',
  '{"id":"e0000000-0000-4000-8000-000000000004","day":813369600,"recordedAt":813413100,"deviceID":"MacA","action":{"pour":{"_0":450}}}');
do $$
declare
 bad jsonb;
 -- The longest real extras event: a 40-character title of 4-byte characters and a
 -- 128-character device ID stays under the unchanged 1,024-byte cap.
 longest jsonb := jsonb_build_object('id','e0000000-0000-4000-8000-000000000005','day',813369600,
   'recordedAt',813413200,'deviceID',repeat('d',128),
   'action',jsonb_build_object('defineExtra',jsonb_build_object('id','E1E1E1E1-0000-4000-8000-000000000002',
     'title',repeat('😀',40))));
begin
 if (select count(*) from public.challenge_events) <> 4 then
   raise exception 'FAIL defineExtra, setExtra and archiveExtra events must insert beside a pour';
 end if;
 insert into public.challenge_events(owner_id,challenge_id,id,activity) values
  ('44444444-4444-4444-8444-444444444444','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','e0000000-0000-4000-8000-000000000005',longest);
 foreach bad in array array[
  '{"id":"e0000000-0000-4000-8000-000000000006","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"notARealAction":true}}',
  '{"id":"e0000000-0000-4000-8000-000000000006","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"setExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","completed":true},"setDiet":{"_0":"clean"}}}',
  '{"id":"e0000000-0000-4000-8000-000000000006","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{}}',
  '{"id":"e0000000-0000-4000-8000-000000000006","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"defineExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000003","title":""}},"extra":1}'
 ]::jsonb[] loop
  begin
   insert into public.challenge_events(owner_id,challenge_id,id,activity) values
    ('44444444-4444-4444-8444-444444444444','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','e0000000-0000-4000-8000-000000000006',bad);
   raise exception 'FAIL malformed event accepted: %', bad;
  exception when check_violation then null; end;
 end loop;
end $$;
reset role;
rollback;
\echo 'PASS: defineExtra, archiveExtra and setExtra insert; unknown, multiple, empty actions and extra keys still rejected.'

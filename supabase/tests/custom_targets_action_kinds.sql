-- Disposable local harness only. No production identities or credentials.
-- After 20261012000100_custom_targets_action_kinds.sql: the three kinds insert in the exact
-- encoding the clients write, including the longest name a client accepts; malformed
-- payloads, unknown slots and units, out-of-range and non-integer values are rejected;
-- the older kinds still insert.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values ('55555555-5555-4555-8555-555555555555');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555"}', true);
insert into public.challenges(owner_id,id,start_time,time_zone) values
 ('55555555-5555-4555-8555-555555555555','ffffffff-ffff-4fff-8fff-fffffffffff1',1791414000,'Europe/London');
do $$
declare
 good jsonb;
 bad jsonb;
 n int := 0;
begin
 foreach good in array array[
  '{"setTarget":{"_0":"walk","name":"Yoga","amount":30,"unit":"minutes","icon":"yoga"}}',
  '{"setTarget":{"_0":"bibleReading","name":"Audiobook","amount":20,"unit":"minutes","icon":"headphones"}}',
  '{"setTarget":{"_0":"workout","name":"Gym"}}',
  '{"setTarget":{"_0":"diet","name":"No sugar"}}',
  '{"setTarget":{"_0":"walk","name":"Steps","amount":10000,"unit":"steps"}}',
  '{"setTarget":{"_0":"bibleReading","name":"😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀","amount":500,"unit":"pages"}}',
  -- 20 characters of two scalars each: a name every client accepts.
  '{"setTarget":{"_0":"walk","name":"👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽"}}',
  '{"setTarget":{"_0":"walk","name":"Hike","amount":60,"unit":"miles"}}',
  '{"setTarget":{"_0":"bibleReading","name":"Psalms","amount":50,"unit":"chapters"}}',
  '{"setTarget":{"_0":"walk","name":"Run","amount":100,"unit":"kilometres"}}',
  '{"setWater":{"goal":1000,"pour":50}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","weekdays":[1,2,3,4,5,6,7]}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","every":30}}',
  '{"setWater":{"goal":3000,"pour":250}}',
  '{"setWater":{"goal":5000,"pour":1000}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","weekdays":[1,2,3,4,5]}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","every":1}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001"}}',
  '{"setHabit":{"_0":"walk","completed":true}}',
  '{"defineExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","title":"Stretch"}}'
 ]::jsonb[] loop
  n := n + 1;
  insert into public.challenge_events(owner_id,challenge_id,id,activity) values
   ('55555555-5555-4555-8555-555555555555','ffffffff-ffff-4fff-8fff-fffffffffff1',
    ('f0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
    jsonb_build_object('id','f0000000-0000-4000-8000-' || lpad(n::text, 12, '0'),'day',813369600,
      'recordedAt',813412800 + n,'deviceID','PhoneA','action',good));
 end loop;
 foreach bad in array array[
  '{"setTarget":{"_0":"water","name":"Water"}}',
  '{"setTarget":{"_0":"yoga","name":"Yoga"}}',
  '{"setTarget":{"_0":"walk","name":""}}',
  '{"setTarget":{"_0":"walk","name":" Yoga"}}',
  '{"setTarget":{"_0":"walk","name":"Line\nbreak"}}',
  jsonb_build_object('setTarget', jsonb_build_object('_0', 'walk', 'name', repeat('x', 81)))::text,
  '{"setTarget":{"_0":"walk","name":"Yoga "}}',
  '{"setTarget":{"_0":"walk","name":7}}',
  '{"setTarget":{"_0":"walk","name":"Yoga","amount":30}}',
  '{"setTarget":{"_0":"walk","name":"Yoga","amount":30,"unit":"hours"}}',
  '{"setTarget":{"_0":"walk","name":"Yoga","amount":301,"unit":"minutes"}}',
  '{"setTarget":{"_0":"walk","name":"Yoga","amount":"30","unit":"minutes"}}',
  '{"setTarget":{"_0":"walk","name":"Yoga","amount":30.5,"unit":"minutes"}}',
  '{"setTarget":{"_0":"diet","name":"No sugar","amount":1,"unit":"pages"}}',
  '{"setTarget":{"_0":"walk","name":"Yoga","icon":"Not An Icon"}}',
  '{"setTarget":{"_0":"walk","name":"Yoga","colour":"red"}}',
  '{"setWater":{"goal":999,"pour":250}}',
  '{"setWater":{"goal":5001,"pour":250}}',
  '{"setWater":{"goal":3000,"pour":49}}',
  '{"setWater":{"goal":1000,"pour":1001}}',
  '{"setWater":{"goal":3000}}',
  '{"setWater":{"goal":"3000","pour":250}}',
  '{"setWater":{"goal":3000.0,"pour":250}}',
  '{"setWater":{"goal":3000,"pour":-250}}',
  '{"scheduleExtra":{"id":"not-a-uuid","every":2}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","every":0}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","every":31}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","weekdays":[]}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","weekdays":[0,8]}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","weekdays":[1],"every":2}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","weekdays":[1.0]}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","weekdays":[1,2,3,4,5,6,7,1]}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","weekdays":1}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","every":2.0}}',
  '{"scheduleExtra":{"id":"E1E1E1E1-0000-4000-8000-000000000001","every":"2"}}',
  '{"setTarget":{"_0":"walk","name":"Yoga"},"setWater":{"goal":3000,"pour":250}}',
  '{"setTarget":{"_0":"walk"}}',
  '{"setTarget":{"name":"Yoga"}}',
  '{"setTarget":{"_0":"walk","name":"Yoga","unit":"minutes"}}',
  '{"setWater":{"pour":250}}',
  '{"scheduleExtra":{"every":2}}',
  '{"setTarget":"walk"}',
  '{"setWater":[3000,250]}'
 ]::jsonb[] loop
  begin
   insert into public.challenge_events(owner_id,challenge_id,id,activity) values
    ('55555555-5555-4555-8555-555555555555','ffffffff-ffff-4fff-8fff-fffffffffff1','f0000000-0000-4000-8000-0000000000ff',
     jsonb_build_object('id','f0000000-0000-4000-8000-0000000000ff','day',813369600,'recordedAt',813412800,
       'deviceID','PhoneA','action',bad));
   raise exception 'FAIL malformed event accepted: %', bad;
  exception when check_violation then null; end;
 end loop;
 if (select count(*) from public.challenge_events) <> n then
   raise exception 'FAIL expected % accepted events', n;
 end if;
 if n <> 20 then raise exception 'FAIL expected 20 accepted events, ran %', n; end if;
end $$;
reset role;
rollback;
\echo 'PASS: setTarget, setWater and scheduleExtra insert in the encoding the clients write; 43 malformed payloads rejected; older kinds unchanged.'

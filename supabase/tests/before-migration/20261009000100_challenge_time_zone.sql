-- Disposable local harness only. Run by scripts/test-sync-security.sh just before
-- the timezone migration: a challenge that already exists when it is applied,
-- like the owner's real one. challenge_time_zone_security.sql checks it afterwards.
\set ON_ERROR_STOP on
insert into auth.users(id) values ('33333333-3333-4333-8333-333333333333');
insert into public.challenges(owner_id,id,start_time) values
 ('33333333-3333-4333-8333-333333333333','99999999-9999-4999-8999-999999999999',1791414000);
insert into public.challenge_events(owner_id,challenge_id,id,activity) values
 ('33333333-3333-4333-8333-333333333333','99999999-9999-4999-8999-999999999999','88888888-8888-4888-8888-888888888888',
  '{"id":"88888888-8888-4888-8888-888888888888","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"pour":{"_0":450}}}');

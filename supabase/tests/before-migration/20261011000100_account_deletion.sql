-- Disposable local harness only. Run by scripts/test-sync-security.sh just before
-- the account deletion migration: an account with a pour and its undo that already
-- exists when the cascades are added. account_deletion_security.sql deletes it afterwards.
\set ON_ERROR_STOP on
insert into auth.users(id) values ('5eed0000-0000-4000-8000-000000000001');
insert into public.challenges(owner_id,id,start_time) values
 ('5eed0000-0000-4000-8000-000000000001','5eed0000-0000-4000-8000-000000000002',1791414000);
insert into public.challenge_events(owner_id,challenge_id,id,activity) values
 ('5eed0000-0000-4000-8000-000000000001','5eed0000-0000-4000-8000-000000000002','5eed0000-0000-4000-8000-000000000003',
  '{"id":"5eed0000-0000-4000-8000-000000000003","day":813369600,"recordedAt":813412800,"deviceID":"MacA","action":{"pour":{"_0":450}}}'),
 ('5eed0000-0000-4000-8000-000000000001','5eed0000-0000-4000-8000-000000000002','5eed0000-0000-4000-8000-000000000004',
  '{"id":"5eed0000-0000-4000-8000-000000000004","day":813369600,"recordedAt":813412900,"deviceID":"MacA","undonePourID":"5eed0000-0000-4000-8000-000000000003","action":{"undoLatestPour":{}}}');

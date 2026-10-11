-- In-app account deletion (App Review Guideline 5.1.1(v)). Apply once, after
-- 20261010000100, before releasing the iPhone build with Delete account
-- (docs/production-sync.md). Transactional; deliberately fails without changes if
-- it already ran. Never run fixture security tests on the hosted project.
begin;

-- Deleting an Auth user removes that owner's rows: the challenge, then its events
-- (sync_probe_entries already cascades). The two foreign keys are re-created with
-- ON DELETE CASCADE under new names; columns, other constraints, RLS and grants are
-- unchanged, so clients still cannot update or delete rows themselves. The undo
-- foreign key stays deferred and NO ACTION: a cascade removes an undo together with
-- the pour it targets.
alter table public.challenge_events
  drop constraint challenge_events_owner_id_challenge_id_fkey,
  add constraint challenge_events_challenge_cascade foreign key (owner_id, challenge_id)
    references public.challenges(owner_id, id) on delete cascade;
alter table public.challenges
  drop constraint challenges_owner_id_fkey,
  add constraint challenges_owner_cascade foreign key (owner_id)
    references auth.users(id) on delete cascade;

-- A signed-in user deletes their own Auth user, and through the cascades all their
-- rows, using only the publishable key and their session. It takes no argument, so
-- nobody can name another account. Calling it again after success changes nothing.
create function public.delete_own_account() returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid();
begin
  if me is null then
    raise exception 'sign in to delete your account' using errcode = '42501';
  end if;
  delete from auth.users where id = me;
end $$;
revoke all on function public.delete_own_account() from public, anon, authenticated;
grant execute on function public.delete_own_account() to authenticated;

commit;

# Self sign-up and password reset

The signed-out popup offers three screens: **Sign in**, **Create account** and **Forgot password?**. A new account is confirmed with a 6-digit code emailed through custom SMTP (Resend). A forgotten password is reset with a 6-digit code too. The code is typed into the popup, so there are no links, no browser round trip and no custom URL scheme. Fixture renders of every screen, Light and Dark, are in [screenshots/sign-up](screenshots/sign-up/).

Until the owner completes the dashboard steps below, existing sign-in keeps working unchanged. Create account shows "New accounts are switched off for this app right now…" while sign-ups are disabled. If sign-ups are enabled before custom SMTP works, Supabase's built-in sender refuses to email non-team addresses and the app says "The app can't send email to that address yet…".

## How the app uses Supabase Auth

| Screen | SDK call (`supabase-swift` 2.55.3) | Result |
| --- | --- | --- |
| Create account | `auth.signUp(email:password:)` | With Confirm email on, Supabase returns a user and **no session**. The app treats that as "code required" and shows the code step, not an error |
| Confirm your email | `auth.verifyOTP(email:token:type: .signup)` | Returns a session; the person is signed in and sees challenge setup |
| Resend code (sign-up) | `auth.resend(email:type: .signup)` | New code; the link shows the 60-second wait instead of a dead button |
| Forgot password? | `auth.resetPasswordForEmail(_:)` | Same answer whether or not the address has an account |
| Choose a new password | `auth.verifyOTP(email:token:type: .recovery)`, then `auth.update(user: UserAttributes(password:))` | The recovery code signs the person in, then the new password is saved for that session |
| Account → Change password | `ProofModel.changePassword(new:)` → `auth.update(user:)` | Requires a signed-in session; the inline form clears both fields on save, failure or Cancel |

The existing rules still hold: password fields (`password`, `passwordConfirmation`, `newPassword`) and the code are cleared after every attempt, success or failure, and when switching screens. Passwords are sent only to Supabase Auth and never stored. Sessions stay in the existing Keychain item. Sign-out stays local-scope. Email addresses are trimmed the same way as sign-in. Error text is plain English for the cases a person can act on and the server's own message otherwise.

Each new account gets its own empty challenge. Row-level security already scopes every row to `auth.uid() = owner_id`, so friends need no schema change and cannot see each other's data.

## Owner-only dashboard setup

The implementation worker must **not** perform these steps, and they must not be done by an automated test.

**The Resend API key is a secret.** Create it yourself and paste it only into the Supabase SMTP **Password** field. Never put it in chat, this repository, `.env.local`, a ticket or a screenshot. The app never needs it.

Do the steps in this order. Sign-ups are switched on last so that no friend can hit a half-configured email path.

### 1. Resend: domain and API key

1. In Resend, open **Domains** and confirm `mail.nextsyntesys.com` shows **Verified**. If it does not, stop here: an unverified domain is exactly what made the 2025 attempt fail (`plans/sync-and-storage.md`).
2. Open **API Keys** → **Create API Key**. Name it something like `Supabase Auth SMTP`. Permission: **Sending access**. Under "Restrict sending to a specific domain", choose `mail.nextsyntesys.com`.
3. Resend shows the key value **once**. Keep the page open and go straight to step 2 below. If you lose it, delete the key and create a new one.

### 2. Supabase: custom SMTP

Open **Authentication → Emails → SMTP Settings** (direct link: https://supabase.com/dashboard/project/ujyvvyrugenknhjodfhc/auth/smtp).

1. Turn on **Enable custom SMTP**.
2. **Sender details**:
   - **Sender email address**: an address on the verified domain, for example `no-reply@mail.nextsyntesys.com`.
   - **Sender name**: `Daily Challenge`.
3. **SMTP provider settings**:
   - **Host**: `smtp.resend.com`
   - **Port number**: `465`
   - **Minimum interval per user**: `60` seconds. The app's "Resend code in …s" countdown assumes 60.
   - **Username**: `resend`
   - **Password**: the Resend API key from step 1.
4. Save. Resend also offers a one-click Supabase integration under its settings; this checklist uses manual entry so every value is visible.

Enabling custom SMTP sets **Authentication → Rate Limits → Rate limit for sending emails** to **30 emails per hour**. That is plenty for a family: each sign-up, resend and reset sends one email. Leave it at 30, and never raise it above what the Resend free plan allows (100 emails per day, 3,000 per month).

### 3. Supabase: the two email templates

Open **Authentication → Emails → Templates**. Edit only these two; leave the others alone.

**Confirm sign up**

- Subject: `Your Daily Challenge code`
- Body:

```html
<h2>Welcome to Daily Challenge</h2>
<p>Your code is:</p>
<p style="font-size: 28px; font-weight: bold; letter-spacing: 4px;">{{ .Token }}</p>
<p>Type it into the Daily Challenge menu-bar app to finish creating your account. It expires in one hour.</p>
<p>If you didn't ask for this, you can ignore this email.</p>
```

**Reset password**

- Subject: `Your Daily Challenge password reset code`
- Body:

```html
<h2>Reset your Daily Challenge password</h2>
<p>Your code is:</p>
<p style="font-size: 28px; font-weight: bold; letter-spacing: 4px;">{{ .Token }}</p>
<p>Type it into the Daily Challenge menu-bar app, then choose a new password. It expires in one hour.</p>
<p>If you didn't ask for this, you can ignore this email. Your password has not changed.</p>
```

Remove `{{ .ConfirmationURL }}` from both templates. The app has no use for a link: clicking it would send the person to the project's Site URL (localhost by default), and email scanners that prefetch links can use up the token.

### 4. Supabase: Email provider settings

Open **Authentication → Sign In / Providers**, then the **Email** provider.

- **Email OTP length**: `6`. The app accepts exactly six digits.
- **Email OTP expiration**: `3600` seconds. The app and the templates say the code expires after an hour.
- **Secure password change**: check it is **off**. If it is on, in-app Change password fails for sessions older than 24 hours with "For security, sign out and use Forgot password…". Password reset by code is not affected.
- **Require current password when updating** (if shown): leave it **off**. The SDK's password update does not send the current password, so Change password would fail.

### 5. Supabase: switch sign-ups on

On **Authentication → Sign In / Providers**, in the **User Signups** section:

1. **Confirm email**: keep it **on**. (Supabase's general-configuration doc still places this under the Email provider; the current dashboard shows it in User Signups.)
2. **Allow new users to sign up**: turn it **on**. Do this last.

With **Confirm email** and **Confirm phone** both on, signing up with an address that already has an account returns a decoy user and sends no email. The decoy still reveals that the address is registered: its `identities` list is empty, which is exactly how the app recognises it and shows "An account with this email already exists, try signing in." Anyone with the publishable key can make the same check, limited only by Supabase's per-IP rate limit on sign-up requests. If Confirm phone is off, Supabase returns `User already registered` instead and the app shows the same message. Signing in to an unconfirmed account also returns `email_not_confirmed`. The invite-only hook in step 7 narrows this: an address that is not on the list gets the hook's 403 instead, so only list membership can be probed.

### 6. Owner acceptance

Use an address you control that is **not** the existing account, for example a Gmail plus alias. Do not use the real account and do not start a challenge with the test account (see Known behaviour about deleting it).

- [ ] Preferably on a Mac that is not signed in to the real account. If you use your own Mac, wait for a synced challenge footer first, then **Sign out on this Mac**. Local data for each account is kept separately and returns when you sign back in.
- [ ] **Create account** → the code arrives from `Daily Challenge <no-reply@mail.nextsyntesys.com>` within a minute (check spam). Resend → **Emails** shows it as delivered.
- [ ] Wrong code → "That code is wrong or has expired…". **Resend code** shows a countdown, then sends a new code. Correct code → signed in, challenge setup appears.
- [ ] Account → **Change password** → new password → "Changed". Sign out and sign in with it.
- [ ] Sign out, **Forgot password?** → code arrives → new password → signed in. Sign out and sign in with the new password.
- [ ] Create account again with the same address → "An account with this email already exists, try signing in."
- [ ] Sign back in to the real account and check the challenge, water and history are unchanged.
- [ ] VoiceOver and keyboard: Tab moves through the fields, Return submits, the code field announces "6-digit code from the email", errors are read as "Error: …".

### 7. Optional hardening: only invited addresses can sign up

Sign-ups stay open to anyone by the owner's decision. Anyone with the app, which embeds the public project URL and publishable key, can create an account. Row-level security keeps their data separate, and the [abuse limits](abuse-limits.md) cap what any one account can store. Open sign-up still lets a stranger use up the project-wide email quota (30 per hour), so friends' codes stop arriving; see [If abuse appears](#if-abuse-appears). If invite-only sign-up is ever wanted, use the **Before User Created** hook (**Authentication → Auth Hooks**; available on the Free plan). It runs only when a new user is created, so existing accounts and sign-ins are unaffected.

The sketch below has been checked only on a disposable local PostgreSQL with Supabase's default `public` privileges emulated (a listed address returns `{}`, a stranger gets the 403, and `anon` and `authenticated` can neither read the list nor call the function), not on a real Supabase stack. Try it first in a disposable local Supabase stack, then in the SQL Editor, then select it as the Before User Created hook (Postgres function) in Auth Hooks. Do not copy the domain example from the Supabase docs as-is; it reads the wrong value.

```sql
create table public.allowed_signup_emails (
  email text primary key check (email = lower(email))
);
alter table public.allowed_signup_emails enable row level security;
-- Supabase grants new public tables to the client roles by default; undo that.
revoke all on public.allowed_signup_emails from anon, authenticated;
-- No client policies: only the Auth server reads this table.
create policy "auth admin reads allowlist" on public.allowed_signup_emails
  for select to supabase_auth_admin using (true);
grant select on public.allowed_signup_emails to supabase_auth_admin;

create function public.hook_allow_listed_signups(event jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.allowed_signup_emails allowed
    where allowed.email = lower(event -> 'user' ->> 'email')
  ) then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object('error', jsonb_build_object(
    'message', 'Sign-ups are invite-only. Ask the person who shared the app with you.',
    'http_code', 403
  ));
end;
$$;

grant execute on function public.hook_allow_listed_signups to supabase_auth_admin;
revoke execute on function public.hook_allow_listed_signups from authenticated, anon, public;
```

Add a friend with `insert into public.allowed_signup_emails values ('friend@example.com');` in the SQL Editor. The app shows the hook's message as written.

## If abuse appears

Signs: friends' codes stop arriving, Resend shows unfamiliar recipients, or the database grows quickly. Owner-only steps, in this order:

1. **Stop new accounts in one step.** **Authentication → Sign In / Providers → User Signups**, turn **Allow new users to sign up** off and save. Existing accounts keep signing in and syncing; Create account in the app then says "New accounts are switched off for this app right now…". Turn it back on when things are quiet.
2. **Check database size and who is writing.** In the SQL Editor (read-only):

   ```sql
   select pg_size_pretty(pg_database_size(current_database()));
   select owner_id, count(*), max(octet_length(activity::text)) from public.challenge_events group by 1 order by 2 desc;
   select owner_id, count(*) from public.sync_probe_entries group by 1 order by 2 desc;
   ```

   The Free plan becomes read-only above 500 MB. No account can exceed 10,000 events or 200 probe rows ([abuse limits](abuse-limits.md)), so a fast-growing database means many accounts. Match an `owner_id` to an address under **Authentication → Users**. Do not delete rows or users without a plan: `challenges.owner_id` has no `on delete cascade` (see Known behaviour).
3. **Email quota.** **Authentication → Rate Limits → Rate limit for sending emails** is the project-wide cap, 30 per hour since custom SMTP was set up in step 2 of the dashboard setup. Leave it there or lower it during an attack; never raise it above the Resend free plan. Supabase also limits sign-up, resend and recovery requests per IP address and sends each address at most one email per 60 seconds.

## Known behaviour

- **Wrong and expired codes look the same.** Supabase answers both with `otp_expired` ("Token has expired or is invalid"), so the app says "That code is wrong or has expired. Check the latest email, or request a new code."
- **Signing up again before confirming keeps the first password.** Supabase resends the code but does not update the stored password. If unsure, use Forgot password after confirming.
- **Signing in before confirming** goes straight to the code step with Resend code available.
- **Reset saves the password after signing in.** If the code is accepted but saving the new password fails (for example the connection drops between the two calls), the person stays signed in and is told the password was not saved and to use Forgot password again.
- **Rate limits.** A second code within 60 seconds is refused; the app shows the wait. Supabase also limits code checks to 30 per 5 minutes per IP address.
- **Deleting an account is not offered.** `challenges.owner_id` has no `on delete cascade`, so deleting a user who started a challenge fails in the dashboard until a migration adds it. A test user that never started a challenge can be deleted.

## Local verification

```bash
swift test --filter ProofAuthTests
DAILY_CHALLENGE_SNAPSHOT_DIR=/tmp/daily-challenge-auth swift test --filter signedOutAuthScreensHaveOpaqueAdaptiveBacking
```

`Tests/ProofAuthTests/SignUpFlowTests.swift` drives the real SDK against an intercepted, stateless synthetic Auth server: sign-up without a session, confirmation, an existing account (decoy user and `user_already_exists`), wrong or expired codes, the 60-second resend limit, recovery and its resend, password update and `same_password`, sign-in before confirming, and field clearing after every attempt. Sessions live in an in-memory store. No real credentials, Keychain, network or email sends are involved. The fixture renders are never-shown native windows, so buttons look inactive; they prove layout and adaptive backing, not real-popup behaviour.

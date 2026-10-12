# Google Play listing drafts (Android)

Drafts for Play Console, modelled on the [App Store listing](app-store-listing.md). Nothing here
has been entered, uploaded or submitted. The app is **free**, has **no ads and no purchases**, and
the wording is generic ("75-day challenge"): the "75 Hard" trademark is not used anywhere in the
app or this listing. Public text has no em or en dashes. The step-by-step owner order is in
[Google Play release checklist](play-release.md).

Limits and requirements were checked on support.google.com and developer.android.com on
12 October 2026; re-check anything Play Console words differently:

- [Store listing assets](https://support.google.com/googleplay/android-developer/answer/9866151): app icon 512 x 512 32-bit PNG up to 1 MB; feature graphic 1024 x 500 JPEG or 24-bit PNG without alpha; phone screenshots JPEG or 24-bit PNG, 320 to 3840 px, the long side at most twice the short side, 2 to 8 per device type, and at least 4 at 1080 x 1920 or more (9:16) to be eligible for promotion; short description 80 characters.
- [Target API level](https://developer.android.com/google/play/requirements/target-sdk): new apps and updates must target API 36 (Android 16) since 31 August 2026. The app targets 36.
- [Testing requirements for new personal accounts](https://support.google.com/googleplay/android-developer/answer/14151465): a closed test with at least 12 testers opted in continuously for at least 14 days before applying for production.
- [Account deletion](https://support.google.com/googleplay/android-developer/answer/13327111): apps that let people create an account must offer deletion in the app and through a web link that works without the app.
- [Data safety](https://support.google.com/googleplay/android-developer/answer/10787469) and the [Health apps declaration](https://support.google.com/googleplay/android-developer/answer/14738291).

## App details

| Field | Draft | Length |
| --- | --- | --- |
| App name | Daily Challenge | 15 / 30 |
| Default language | English (United Kingdom), en-GB | |
| App or game | App | |
| Free or paid | Free (cannot be changed to paid later) | |
| Category | Health & Fitness | |
| Tags (up to 5, chosen from Play's list) | Habit tracker, Fitness tracking, Water tracker, To-do list, Productivity (pick the closest names Play offers) | |
| Contact email | yakovetskyi@icloud.com | |
| Website | `https://nikobenzo.github.io/daily-challenge/` | |
| Phone | Leave empty (optional) | |
| Privacy policy URL | `https://nikobenzo.github.io/daily-challenge/privacy.html` | |
| Account deletion URL (Data safety) | `https://nikobenzo.github.io/daily-challenge/delete-account.html` | |

The developer name shown on Play is the account's ("okin"). The privacy policy and deletion page
name Mykola Yakovetskyi as the person responsible; if Play shows "okin", that is fine, as the pages
also name the app as it appears on the listing ("Daily Challenge"). The deletion page and the
Android lines of the privacy policy go live when `site/` reaches `main` and the Pages workflow
runs ([site/README.md](../site/README.md)); open both URLs before pasting them.

## Short description (78 / 80)

```text
A 75-day challenge tracker: water, workout, walk, diet and reading, every day.
```

## Full description (1,378 / 4,000)

```text
Daily Challenge keeps a 75-day challenge simple. Every day you have five things to do. Log them in a few taps, and see your streak grow.

THE FIVE DAILY REQUIREMENTS
• Water: a drawn jug fills as you log pours towards 4 litres. Add 450 ml in one tap, or log any amount.
• Workout and walk: mark each one done, or undo it.
• Diet: mark the day as pending, clean or missed.
• Bible reading: tick it off when you have read.

YOUR STREAK
See your current streak out of 75, your best streak, and milestones along the way. Tracking carries on after day 75.

EXTRAS
Add up to ten personal to-dos of your own. They carry over, marked Late, until you finish them. Extras never count towards a complete day or your streak.

HISTORY
Open the monthly calendar to see every day at a glance, and tap Edit this day to fix a missed tick or a pour you forgot.

WATER REMINDERS
Optional reminders at the interval and hours you choose, which stop once you reach your goal.

ON ALL YOUR DEVICES
Sign in with your email and your progress syncs between your Android phone, iPhone and Mac. Everything is saved on your phone first, so nothing is lost when you are offline.

LIGHT AND DARK
Follows your phone's dark mode, or choose Light or Dark yourself.

PRIVATE BY DESIGN
No ads, no tracking and no analytics. You can delete your account and all of your data inside the app.

Free, with no purchases.
```

The lengths are checked by the snippet at the end of this file. Unlike the iPhone text, there is no
widgets paragraph: the Android app has no widgets yet. Add one when they ship.

## Graphics

All in [`docs/assets/play/`](assets/play/), rendered by `scripts/render-play-assets.py` (its
docstring has the run command):

| File | Play field | Notes |
| --- | --- | --- |
| `icon-512.png` | App icon | 512 x 512, 32-bit PNG. The same tile as the iPhone icon (`scripts/render-app-icon.swift --ios`) and the Android launcher icon; full bleed, because Play applies the rounded mask. |
| `feature-graphic-1024x500.png` | Feature graphic | 1024 x 500, 24-bit PNG. The App Store header's style with the real Android Today card; source `docs/assets/play/source/feature-graphic.html`. |
| `screenshots/01-today-extras-light.png` | Phone screenshot 1 | Today with extras, two of them Late |
| `screenshots/02-today-complete-light.png` | Phone screenshot 2 | All five complete |
| `screenshots/03-history-light.png` | Phone screenshot 3 | Monthly calendar and a complete day |
| `screenshots/04-setup-light.png` | Phone screenshot 4 | "Your next 75 days" setup |
| `screenshots/05-account-light.png` | Phone screenshot 5 | Water reminders and appearance |
| `screenshots/06-today-dark.png` | Phone screenshot 6 | Today in Dark |

The screenshots are 1080 x 1920 (9:16), 24-bit PNG, made from the Redmi Note 7 fixture captures in
`docs/screenshots/android/` with the phone's status and navigation bars cropped off and the app
scaled to fit, with its own background continued into narrow side margins. No captions or frames.
Caveats, as for the iPhone set: the fixtures run offline, so Today, History and setup show a "Local
only" chip and Account shows "Saved on this phone only, not connected to the server" and the
sample address `sam@example.com`. Drop `05-account-light.png` (five screenshots still qualify) or
recapture Account from the reviewer test account if that reads badly. Phone screenshots are enough to
publish; tablet and other form factors are optional.

## App content (Policy > App content)

| Form | Answer |
| --- | --- |
| Privacy policy | `https://nikobenzo.github.io/daily-challenge/privacy.html` |
| Ads | No, the app does not contain ads |
| App access | All or some functionality is restricted: see [App access](#app-access-instructions-for-reviewers) |
| Content rating | Questionnaire below |
| Target audience | 18 and over (see below) |
| News app | No |
| Data safety | Answers below |
| Government app | No |
| Financial features | None |
| Health apps | Activity and fitness; Nutrition and weight management (self-logged water, workouts, walks, diet). Not a medical app; no Health Connect access. |
| Advertising ID | No: the app does not use an advertising ID (the merged manifest has no `AD_ID` permission). |

## Data safety

Grounded in the code (`android/core`): the app talks only to Supabase over HTTPS (cleartext is
disabled in the manifest); it sends the email and password to Supabase Auth to sign in, and writes
the challenge record (start time, time zone) and each entry (kind, amount or mark, day, time and
the per-install device ID) to Supabase. Account emails go through Resend. There is no analytics,
crash reporting, ads or other third-party SDK: the dependencies are AndroidX, Jetpack Compose,
Kotlin coroutines, kotlinx.serialization and OkHttp. Water reminders are local alarms and
notifications. Supabase and Resend act for the developer, so they are service providers, not
sharing.

**Overview**

| Question | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | Yes |
| Is all of the user data collected by your app encrypted in transit? | Yes |
| Which of the following methods of account creation does your app support? | Username and password (email address and password) |
| Account deletion URL | `https://nikobenzo.github.io/daily-challenge/delete-account.html` |
| Do you provide a way for users to request that some or all of their data is deleted, without requiring them to delete their account? | No (deleting the account deletes all data; individual entries can be corrected in History) |

**Data types** (all: collected yes, shared no, not processed ephemerally, required, not optional)

| Category › type | What it is | Purposes |
| --- | --- | --- |
| Personal info › Email address | Sign-in email | App functionality, Account management |
| Personal info › User IDs | The account ID that links the challenge rows to the account | App functionality, Account management |
| Health and fitness › Fitness info | Water amounts, workout, walk, diet and reading marks, start date and time zone | App functionality |
| App activity › Other user-generated content | The names of the user's extras | App functionality |
| Device or other IDs › Device or other IDs | A random ID created per install and attached to each synced entry; not an advertising or hardware ID | App functionality |

Not collected: location, contacts, photos, videos, audio, files, calendar, messages, web browsing,
installed apps, app interactions or search history (no analytics), crash logs and diagnostics,
financial info, other personal info. Device-local settings (reminders, appearance) never leave the
phone.

Owner checks before submitting: (1) the reading requirement is labelled Bible reading; it is a
yes/no habit mark, recorded here under Fitness info as on the App Store. If you would rather be
conservative, also tick Personal info › Political or religious beliefs (App functionality);
(2) the password is sent to Supabase Auth only to sign in and is stored there only as a hash; Play
has no password data type, so it is covered by the account-creation answer, matching the iPhone
answers; (3) that no SDK has been added since this draft (`./gradlew :app:dependencies` and the
merged manifest).

## Content rating (IARC questionnaire)

Email for the rating certificate: yakovetskyi@icloud.com. Category: **All other app types**
(not a game, not social, not a news or reference app).

| Question | Answer |
| --- | --- |
| Violence, blood, gore | No |
| Fear, horror | No |
| Sexuality, nudity | No |
| Language (profanity, crude humour) | No |
| Controlled substances (drugs, alcohol, tobacco) | No |
| Gambling, simulated gambling | No |
| Does the app allow users to interact or exchange content with each other? | No (extras are private to-dos; nothing is shared between accounts) |
| Does the app share the user's current physical location with other users? | No |
| Does the app allow users to purchase digital goods? | No |
| Is the app a web browser or search engine? | No |
| Does the app contain hate speech, terrorism or other unmoderated content? | No |

Expected result: Everyone / PEGI 3 / USK 0 and equivalents. Accept what IARC calculates.

## Target audience and content

- Target age groups: **18 and over**. The app is a self-improvement tracker for adults; the
  privacy policy says it is not directed at children under 13. Do not tick any group under 13,
  which would bring in the Families policy. 16 to 17 can be added later if wanted.
- Could the store listing unintentionally appeal to children? No.
- Ads: none.

## App access instructions for reviewers

Choose **All or some functionality is restricted** and add one set of instructions. Create the
reviewer account on the production server before submitting (create it in the app with a real
inbox, confirm the code, start a challenge and log a few days), keep it out of real use, and never
commit its password.

| Field | Value |
| --- | --- |
| Name | Reviewer account |
| Username | `[REVIEWER ACCOUNT EMAIL]` |
| Password | `[REVIEWER ACCOUNT PASSWORD]` |
| Any other information | Text below |

```text
Daily Challenge is a personal tracker for a 75-day daily challenge: water (4 litres), workout,
walk, diet and reading, plus optional personal to-dos ("extras").

Sign in on the first screen with the email and password above. The account already has a challenge
in progress, so no setup is needed. New accounts are created in the app with an emailed code; the
reviewer account does not need one.

Try: Today (tap + 450 ml, tick a requirement), History (calendar, Edit this day), Account (water
reminders, appearance, Manage extras). Notifications are optional local water reminders, requested
only when reminders are turned on (Android 13 and later).

Account deletion: Account > Delete account (permanently deletes the account and its data). Please
do not delete the reviewer account. No ads, tracking, purchases or third-party analytics.
Contact: yakovetskyi@icloud.com
```

## Release notes for the first closed test (en-GB)

```text
First test release of Daily Challenge for Android. Sign in with your Daily Challenge account or
create one, then log today's water, workout, walk, diet and reading. Please report anything odd
to yakovetskyi@icloud.com.
```

## Closed test and production access

The account is a personal account created after November 2023, so production needs a closed test
first: **at least 12 testers opted in continuously for at least 14 days**. Opting out and back in
restarts that tester's days. Google may ask for more testing if engagement is low. Re-check the
rule on the Play Console dashboard when the test starts; it shows the live count and days.

Tester opt-in flow:

1. Testers are added by email list (Testing > Closed testing > the track > Testers > Create email
   list) or a Google Group. Each tester's address must be the Google account they use on their
   Android phone.
2. After the first release on the track is reviewed and published, Play Console shows the **opt-in
   link** (Testers tab, "Join on the web"). Send it to every tester.
3. Each tester opens the link signed in to that Google account, taps **Become a tester**, then
   installs Daily Challenge from the Play Store link on that page. Installing from Play is what
   counts; a sideloaded APK does not.
4. Ask testers to open the app on several days and to stay opted in for the whole 14 days.
   Recruit about 15 to 20 so that drop-outs do not take the count below 12.

When the dashboard shows the requirement met, **Apply for production** asks about the closed test
(how testers were recruited, how engaged they were, feedback summary), the app (audience, value,
expected installs in the first year) and production readiness (what changed after testing). Review
usually takes up to 7 days. Keep notes during the test for these answers.

## Length check

```sh
python3 - <<'EOF'
import re
text = open('docs/play-store-listing.md', encoding='utf-8').read()
blocks = re.findall(r'```text\n(.*?)\n```', text, re.S)
print('short', len(blocks[0]), '/ 80; full', len(blocks[1]), '/ 4000')
assert not re.search('[\u2013\u2014]', '\n'.join(blocks)), 'dash found'
EOF
```

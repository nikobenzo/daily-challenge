# Google Play release checklist (owner steps)

The owner's path from a verified Google Play developer account to a live closed test and then
production. Everything to type into Play Console is in [Google Play listing drafts](play-store-listing.md);
build details are in [Android app](android.md). Nothing in this repository uploads anything or
signs in to Play Console.

The account is a **personal** account created after November 2023, so the app needs a closed test
with at least 12 testers opted in for 14 days in a row before production access can be requested.

## What is ready in the repository

- Release signing that reads the upload key from outside the repository and refuses a release
  build without it (`android/app/build.gradle.kts`), and `scripts/android-upload-key.sh` to create
  the key.
- `./gradlew bundleRelease`: a signed Android App Bundle, minified and shrunk with R8, targetSdk 36.
- The account deletion page `site/delete-account.html`, and the privacy policy updated for Android.
- Store text, Data safety, content rating and reviewer instructions: [listing drafts](play-store-listing.md).
- Store graphics: `docs/assets/play/` (icon, feature graphic, eight phone screenshots).

## 1. Before you start

- [ ] Identity verification for the developer account is complete (Play Console shows no
      verification banner). If Play Console asks you to confirm access to an Android phone, do
      it with the Play Console app on the Redmi Note 7 or any Android phone.
- [ ] Push `main` so the Pages workflow publishes the site, then open
      `https://nikobenzo.github.io/daily-challenge/delete-account.html` and
      `https://nikobenzo.github.io/daily-challenge/privacy.html` and check both load and mention
      Android.
- [ ] Confirm the package name `app.dailychallenge.android`. It is permanent after the first upload.
- [ ] The hosted migrations are deployed, including `20261011000100_account_deletion`
      ([production sync](production-sync.md)), since the app offers in-app deletion.

## 2. Create the upload key (once)

Play App Signing keeps the key that signs the app people install; you only keep an **upload key**
that proves uploads come from you. If it is ever lost, Google can reset it (it takes a few days),
but back it up so that never happens.

```sh
bash scripts/android-upload-key.sh
```

- keytool asks for a password twice. Choose a strong one and save it in your password manager
  first. It is never passed on the command line.
- The keystore is written to `~/.android-keys/daily-challenge-upload.jks` (alias `upload`), with
  the folder readable only by you. Pass another path as the first argument if you prefer; the
  script refuses a path inside the repository and never overwrites an existing keystore.
- [ ] Back up the `.jks` file and its password together, for example as an attachment in your
      password manager. Never commit it (`*.jks` and `*.keystore` are gitignored) and never send it
      to anyone, Google included.
- [ ] Tell Gradle where it is. Add to `~/.gradle/gradle.properties` (your home folder, outside the
      repository), then run `chmod 600 ~/.gradle/gradle.properties`:

  ```properties
  DC_UPLOAD_STORE_FILE=/Users/<you>/.android-keys/daily-challenge-upload.jks
  DC_UPLOAD_KEY_ALIAS=upload
  DC_UPLOAD_STORE_PASSWORD=<the password>
  ```

  Or export the same three names as environment variables in the shell that builds, if you would
  rather not keep the password in a file. `DC_UPLOAD_KEY_PASSWORD` is only needed if the key's
  password differs from the keystore's (it does not, for keys the script creates).

## 3. Build the release bundle

```sh
cd android
./gradlew bundleRelease
```

- Needs the real `.env.local` (Supabase URL and publishable key) at the repository root, as for
  any release build; without it, or without the upload key settings, the build stops with a
  message saying what is missing.
- Output: `android/app/build/outputs/bundle/release/app-release.aab`.
- Check it is signed with your upload key:
  `keytool -printcert -jarfile app/build/outputs/bundle/release/app-release.aab` shows
  `CN=Mykola Yakovetskyi, O=Daily Challenge` and the same SHA-256 as
  `keytool -list -v -keystore ~/.android-keys/daily-challenge-upload.jks`.

**Version numbers.** `versionCode` in `android/app/build.gradle.kts` counts uploads: start at 1 and
raise it by one for every bundle uploaded to any track (internal, closed or production), even
if the previous one was never released. Play rejects a versionCode it has seen before, and it can
never go down. `versionName` (`1.0`) is what people see; raise it for user-visible releases, in
step with the iPhone version where it makes sense. Commit each change so the repository records
which code was uploaded.

**Optional local check.** `./gradlew assembleRelease` builds a release APK signed with the same
upload key (`app/build/outputs/apk/release/app-release.apk`), which installs on the Redmi through
the Download route in [Android app](android.md#install-on-a-phone). Uninstall it again before
installing from Play: Play's copy is signed with Google's app signing key, so Android treats the
two as different signers.

## 4. Create the app in Play Console

- [ ] **Create app**: app name `Daily Challenge`, default language English (United Kingdom),
      App, Free; accept the declarations (Developer Program Policies, US export laws).
- [ ] **Store presence > Main store listing**: app name, short and full description from the
      [listing drafts](play-store-listing.md); upload `docs/assets/play/icon-512.png`,
      `feature-graphic-1024x500.png` and the eight files in `docs/assets/play/screenshots/` in their
      numbered order.
- [ ] **Store presence > Store settings**: category Health & Fitness, tags, contact email
      `yakovetskyi@icloud.com`, website.
- [ ] **Policy > App content**: complete each form from the listing drafts: Privacy policy, Ads
      (no), App access (reviewer account, step 5), Content rating, Target audience (18 and over),
      News app (no), Data safety (including the account deletion URL), Government app (no),
      Financial features (none), Health apps, Advertising ID (no).

## 5. Reviewer account

- [ ] In the app, create a dedicated account with an inbox you control, confirm the code, start a
      challenge and log a few days of entries. Keep it out of real use.
- [ ] Enter its email and password only in Play Console (App content > App access), with the
      instructions text from the listing drafts. Never commit them or paste them into an issue.

## 6. Optional: internal test on your own phone first

Internal testing needs no review and shows within minutes, so it is a quick check of the Play
build on the Redmi. It does not count towards the 12 testers and 14 days.

- [ ] Testing > Internal testing > Testers: add your own Google account. Create a release, upload
      the AAB, and accept **Play App Signing** with a Google-generated key when asked (the default).
- [ ] On the Redmi, uninstall any Debug or sideloaded build first (sync first: this deletes the
      phone's local copy), open the internal test link signed in to the same Google account,
      accept, and install from the Play Store. Run the owner acceptance checklist in
      [Android app](android.md#owner-acceptance-checklist-real-account-real-phone).

## 7. Closed test

- [ ] Testing > Closed testing: use the default track (or create one), choose countries (all, as
      for the iPhone app).
- [ ] Testers tab: create an email list with the testers' Google account addresses (or use a Google
      Group). Aim for 15 to 20 people so that 12 stay opted in.
- [ ] Create a release: upload the AAB (accept Play App Signing if this is the first upload),
      release name `1.0 (1)`, release notes from the listing drafts, then **Save**, **Review
      release** and **Start rollout to Closed testing**.
- [ ] Publishing overview: **Send changes for review**. The first review can take several days.
- [ ] When the release shows as available, copy the **opt-in link** from the track's Testers tab
      and send it to the testers with three instructions: open it signed in to the Google account
      you gave, tap **Become a tester**, then install Daily Challenge from the Play Store link on
      that page; and stay opted in for at least 14 days, opening the app now and then.
- [ ] Watch the dashboard: it shows how many testers are opted in and for how many days. Keep notes
      on feedback and fixes; the production application asks for them.
- [ ] Fixes during the test: raise `versionCode`, build, upload a new release to the same closed
      track. Testers stay opted in; their 14 days continue.

## 8. Apply for production

- [ ] When the dashboard shows at least 12 testers opted in for 14 continuous days, choose
      **Apply for production** and answer the three sections: the closed test (how you recruited
      testers, their engagement, feedback), the app (audience, value, expected installs in the first
      year) and readiness (what changed after testing). Re-check the rule wording on the dashboard;
      Google can ask for more testing if engagement was low.
- [ ] After approval (usually within 7 days): Production > Create release, reuse the tested bundle
      from the library (or upload a newer one with a higher `versionCode`), roll out (a staged
      rollout such as 20% is a safe start), and send for review.

## Lost upload key

Play Console > Test and release > App integrity > App signing > **Request upload key reset**. Make
a new key with the script (a new path), export its certificate with
`keytool -export -rfc -keystore <new.jks> -alias upload -file upload_certificate.pem`, and attach
the PEM to the request. Update `~/.gradle/gradle.properties` once Google confirms.

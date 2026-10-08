# Releases and automatic updates

Daily Challenge updates itself with [Sparkle 2](https://sparkle-project.org) (pinned to 2.10.0 in `Package.swift`). Once a day the installed app reads an appcast (`appcast.xml`) from the feed URL built into it. When the appcast lists a higher `CFBundleVersion`, the app shows Sparkle's update window, and the friend clicks **Install Update**. Sparkle then downloads the zip, checks its EdDSA signature against the public key built into the app, checks that the new app has the same Developer ID signature, replaces the app and relaunches it. Friends can also use **Account › About › Check for updates** at any time.

> **Open decision: where to host the feed.** The GitHub repository is private, so its release assets cannot be downloaded by friends. Nothing is uploaded until the owner chooses an HTTPS host for `appcast.xml` and the zips (for example GitHub Pages plus Releases on a public repository, or any static file host). That URL becomes `SPARKLE_FEED_URL`. Choosing and configuring the host, and publishing the first release, are separate steps from this setup.

## One-time setup (owner)

1. **Create the signing key.** Run Sparkle's tool from the project folder (after `swift package resolve`):

   ```bash
   .build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

   It stores the private key in your login keychain as "Private key for signing Sparkle updates" and prints the public key. The private key never leaves the keychain and is never committed or pasted anywhere. If it is lost, installed copies can no longer be updated and friends must reinstall by hand once, so back it up with `generate_keys -x <file>` to somewhere safe and offline if you want a copy.
2. **Add both values to `.env.local`** (see `.env.example`):

   ```bash
   SPARKLE_FEED_URL=https://<chosen host>/appcast.xml
   SPARKLE_PUBLIC_ED_KEY=<the public key printed by generate_keys>
   ```

   Both are public. `scripts/build-proof.sh` writes them into Info.plist as `SUFeedURL` and `SUPublicEDKey` and refuses to make a shareable build without them. `--adhoc` builds may leave them out; the app then shows "Updates are off in this development build". The feed URL must be `https://`; plain `http://` is accepted only for `127.0.0.1` testing.
3. **Get the first update-capable version to friends by hand.** Version 0.2.0 and earlier copies have no updater. Every friend installs one Sparkle-enabled build the usual way ([friends guide](getting-started-for-friends.md)); after that, updates arrive in the app.

Never change `SPARKLE_FEED_URL` or the key for builds friends already have unless you also keep serving the old feed: an installed app only knows the URL and key it was built with.

## Each release (owner)

1. **Bump `VERSION`.** Raise `CFBundleShortVersionString` (for example `0.3.0`) and always raise `CFBundleVersion` (`2` → `3`). Sparkle compares `CFBundleVersion`, so it must only ever go up, and `scripts/release.sh` refuses to stage a number twice.
2. **Build:** `bash scripts/build-proof.sh` (signed, notarized, stapled `build/DailyChallenge.zip`).
3. **Stage:** `bash scripts/release.sh`. It checks that the zip holds the notarized app for `VERSION` with a feed, copies it to `releases/DailyChallenge-<version>-<build>.zip`, and runs Sparkle's `generate_appcast` over `releases/`. That tool reads the private key from your keychain (macOS may ask you to allow access; choose **Allow**) and signs the zip into `releases/appcast.xml`. It keeps the three newest versions in the appcast and moves older zips to `releases/old_updates/`. Delta updates are turned off, so each release is one zip. `releases/` is ignored by git; keep it between releases, because the next run updates the same `appcast.xml`.
   - Enclosure URLs default to the folder of `SPARKLE_FEED_URL`. If the zips live somewhere else (for example on a GitHub release page), pass `--download-url-prefix https://<where the zip will be>/`.
   - Optional release notes: put `DailyChallenge-<version>-<build>.md` (or `.html`) next to the zip in `releases/` before running the script, and Sparkle shows it in the update window.
4. **Upload** the two files the script names (`releases/appcast.xml` and the new zip) to the feed host. Upload the zip first, then the appcast, so no friend reads an appcast whose zip is missing. The script itself never uploads anything.
5. **Check:** on a Mac with the previous version, click **Account › About › Check for updates**; Sparkle should offer the new version.

## How the app behaves

- **Checks:** `SUEnableAutomaticChecks` is on and `SUScheduledCheckInterval` is 86400 (daily), so friends are not asked whether to check. Downloading and installing still waits for the friend's click (`SUAutomaticallyUpdate` keeps Sparkle's default, off). Sparkle's window also offers to install future updates automatically, which a friend may accept.
- **Menu-bar app:** the app has no Dock icon (`LSUIElement`). `SoftwareUpdates.swift` activates the app before Sparkle shows a window, so the update window comes to the front. A check that finds an update soon after launch (for example at login) shows the window straight away. Later background finds do not take focus from another app (Sparkle's gentle reminders); the About group shows "Version X is available" with **Install update** until the friend acts.
- **Bundle contents:** `Sparkle.framework` (with `Autoupdate` and `Updater.app`) is embedded in `Contents/Frameworks`. Sparkle's Downloader and Installer XPC services are left out because they are only needed by sandboxed apps (Sparkle's sandboxing guide), so `SUEnableInstallerLauncherService` is not set. Each nested item is signed explicitly with the Developer ID and hardened runtime, innermost first, then the framework, then the app. `--deep` is never used for signing.
- **Keychain session, login item and data** stay the same through an update, because the bundle identifier, signature and install location do not change.
- **Apple silicon only:** builds made on an Apple silicon Mac contain only arm64 code, and `generate_appcast` records `arm64` as a hardware requirement, so Intel Macs are not offered updates (they cannot run the app either).

Verification evidence: [update verification](update-verification.md).

# Automatic update verification

Recorded 9 October 2026 on Apple silicon, macOS 27.0.1 (26A434), Xcode 27, Sparkle 2.10.0. Owner steps are in [releases](releases.md).

**Scope and limits.** The worker used a throwaway EdDSA key held only in a file under the ignored `build/` folder, a placeholder feed URL (`https://updates.invalid/daily-challenge/appcast.xml`) for the real app, and a feed served from `127.0.0.1` for the fixture. No key was added to any keychain (Sparkle's `generate_keys` always uses the login keychain, even with `-f`, so it was not run; the key is a CryptoKit Ed25519 seed in Sparkle's key-file format). Nothing was uploaded except the build to Apple's notary service. The running `/Applications/Daily Challenge.app` was not quit, replaced or launched, and no real account, Keychain session or challenge file was read. **The real Daily Challenge app has not yet updated itself from a hosted feed:** that needs the feed host decision and is owner acceptance below.

## 1. Notarized build with Sparkle embedded

`bash scripts/build-proof.sh` with `SIGNING_IDENTITY`, the throwaway public key and the placeholder feed:

```text
$ notarytool
  id: e5adc5ff-d0d8-4279-918c-df27d1643210
  status: Accepted
$ codesign --verify --strict --deep --verbose=2
build/Daily Challenge.app: valid on disk
build/Daily Challenge.app: satisfies its Designated Requirement
$ spctl --assess --type execute -vv
build/Daily Challenge.app: accepted
source=Notarized Developer ID
origin=Developer ID Application: Mykola Yakovetskyi (L644Y3WX5T)
$ stapler validate
The validate action worked!
$ nested signatures (each Developer ID, hardened runtime, secure timestamp)
Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate: flags=0x10000(runtime)
Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app: flags=0x10000(runtime)
Contents/Frameworks/Sparkle.framework: flags=0x10000(runtime)
.: flags=0x10000(runtime)
$ rpaths (SwiftPM's absolute build-folder rpaths removed)
  /usr/lib/swift
  @loader_path
  @executable_path/../Frameworks
$ XPC services in the bundle: 0
$ Info.plist
    SUFeedURL = https://updates.invalid/daily-challenge/appcast.xml
    SUPublicEDKey = <throwaway public key>
    SUEnableAutomaticChecks = true
    SUScheduledCheckInterval = 86400
    CFBundleShortVersionString = 0.2.0
    CFBundleVersion = 2
```

Build guards: without `SPARKLE_PUBLIC_ED_KEY` a default build stops with "SPARKLE_FEED_URL and SPARKLE_PUBLIC_ED_KEY must both be set"; `--adhoc` prints a notice, omits the `SU*` keys and still passes `codesign --verify --strict --deep`; `SPARKLE_FEED_URL=http://example.com/...` is rejected.

## 2. Appcast for the built zip

`bash scripts/release.sh --ed-key-file <throwaway key>` staged `releases/DailyChallenge-0.2.0-2.zip` and wrote `releases/appcast.xml` (item `sparkle:version` 2, `shortVersionString` 0.2.0, `minimumSystemVersion` 14.0, `hardwareRequirements` arm64, enclosure under the feed URL's folder, with `sparkle:edSignature`). `sign_update --verify` accepted that signature for the zip, and `xmllint --noout` found the appcast well formed. Running the script again with a different `0.2.0 (2)` zip already staged stopped with "already staged with different contents; raise CFBundleVersion".

## 3. End-to-end update fixture

`bash scripts/test-update-fixture.sh --ed-key-file <throwaway key>` builds an isolated fixture (bundle ID `app.daily-challenge.update-fixture`) from the app's own `SoftwareUpdates.swift`. Sparkle is embedded, trimmed and Developer ID signed the same way as the app, and `LSUIElement` is set. The script serves a signed appcast from `127.0.0.1` with `python3 -m http.server`, then removes the fixture's preferences and caches. Result of the final run:

```text
launched 1.0 (1) mode=interactive activationPolicy=1
found-update 1.1 (2) url=http://127.0.0.1:8765/UpdateFixture-1.1-2.zip
onscreen-windows=[21314] visible-titles=["Software Update"] frontmost=true dockIcon=false
launched 1.0 (1) mode=silent activationPolicy=1
found-update 1.1 (2) ...
downloaded 2
extracted 2
install-on-quit 2; installing now
installing 2
launched 1.1 (2) mode=silent activationPolicy=1
no-update You're up to date!

Wrong-key 1.2:
launched 1.1 (2) mode=silent
found-update 1.2 (3) ...
downloaded 3
extracted 3
aborted SUSparkleErrorDomain 4005 The update is improperly signed and could not be validated.

PASS: 1.0 found, showed and installed 1.1; a wrongly signed 1.2 was refused (installed: 1.1)
```

This shows four things:

- A user-initiated check (`SoftwareUpdates.checkForUpdates()`) finds the newer version and puts Sparkle's **Software Update** window on screen, even though the app has no Dock icon (`activationPolicy=1`, accessory).
- With automatic installation allowed, Sparkle downloads, validates, installs and relaunches the fixture as 1.1.
- Sparkle extracts before it validates (its default, `SUVerifyUpdateBeforeExtraction` off), but it refuses to install an update signed with any other key (error 4005).
- The installed 1.1 still passes `codesign --verify --strict --deep`.

**Activation.** On macOS 14 and later, activation is cooperative, so `NSApp.activate()` is a request the system may decline while another app is in use. Across 11 fixture runs launched from Terminal during interactive use, the update window was on screen every time and frontmost in 8. In the other 3 it sat behind the active app. The deprecated `activate(ignoringOtherApps:)` was also declined in 1 of 5 runs, so it was not adopted. The fixture therefore requires the window on screen and only records frontmost. In the real app, a user-initiated check starts from a click in the app's own popup, which normally makes the app active already. Confirming that is real-popup acceptance.

## 4. Automated tests

`swift test`: 124 tests passed (52 + 22 + 9 + 41). The new tests:

- `updatesNeedBothFeedKeys`: `SoftwareUpdates` starts only when both keys are present.
- `unconfiguredBuildNeverStartsTheUpdater`: a bundle without a feed creates no updater and makes check a no-op.
- `accountTabRendersInLightAndDark`: renders the About row, including the new `account-tab-update-available-*.png` in `docs/screenshots/account-tab/`.

## Not verified; owner acceptance

1. Choose the feed host, run `generate_keys`, and set `SPARKLE_FEED_URL`/`SPARKLE_PUBLIC_ED_KEY`.
2. Build and install version N on a Mac by hand, then build N+1 and run `scripts/release.sh`. Upload the zip, then `appcast.xml`.
3. On the Mac with N: click **Account › About › Check for updates**. The Software Update window should come to the front. Click **Install Update**; the app relaunches as N+1, still signed in, with history intact, and Launch at login still works.
4. Leave N installed past a daily check, and confirm the window at launch, or the About row's "Version X is available" for a check that finds an update later. The gentle-reminder About row has only been rendered, not triggered natively.

`generate_appcast` keeps its own extraction cache in `~/Library/Caches/Sparkle_generate_appcast`. It was left in place because it is the tool's shared cache.

# Developer ID signing and notarization verification

`scripts/build-proof.sh` signs with the Developer ID Application identity and the hardened runtime, notarizes with the `dc-notary` keychain profile, staples, re-zips and requires Gatekeeper acceptance. `--adhoc` is the explicit local-only path; `--skip-notarize` stops after signing.

Verified on 8 October 2026 on the build Mac (Apple Silicon, macOS 27.0.1, Xcode 27 tools) in a disposable worktree whose `.env.local` held the real public configuration plus `SIGNING_IDENTITY=Developer ID Application: Mykola Yakovetskyi (L644Y3WX5T)`. The running `/Applications/Daily Challenge.app`, the real account and its Keychain session were not touched; the built app was not launched.

## Tests

`swift test`: 122 tests passed (50 + 22 + 9 + 41 across the four Swift Testing runs), 0 failures.

## Guard paths

| Invocation | Result |
|---|---|
| No `SIGNING_IDENTITY` anywhere | exit 1: "No SIGNING_IDENTITY set (environment or .env.local), so this build cannot be shared." plus the `--adhoc` hint |
| `SIGNING_IDENTITY` not in the keychain | exit 1: "Signing identity not found in the keychain: …" |
| Unknown option | exit 2 |
| `--adhoc` | `Signature=adhoc`, `TeamIdentifier=not set`; ends with "!!! AD-HOC BUILD: for this Mac only, NOT shareable; … !!!" |
| Default, `dc-notary` profile not yet stored | signs and verifies, then exit 1: `Notarization credential profile "dc-notary" is missing or invalid.` with the `store-credentials` hint |

## Developer ID signature

```
$ codesign --verify --strict --deep --verbose=2 "build/Daily Challenge.app"
build/Daily Challenge.app: valid on disk
build/Daily Challenge.app: satisfies its Designated Requirement

$ codesign -dvv --entitlements - "build/Daily Challenge.app"
Identifier=app.daily-challenge.proof
Format=app bundle with Mach-O thin (arm64)
CodeDirectory v=20500 size=20389 flags=0x10000(runtime) hashes=630+3 location=embedded
Authority=Developer ID Application: Mykola Yakovetskyi (L644Y3WX5T)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
Timestamp=8 Oct 2026 at 23:07:23
TeamIdentifier=L644Y3WX5T
Runtime Version=14.0.0
(no entitlements printed)

$ codesign -dv ".../Contents/Resources/swift-crypto_Crypto.bundle"
CodeDirectory v=20200 size=221 flags=0x10000(runtime) hashes=1+3 location=embedded
Timestamp=8 Oct 2026 at 23:07:23
TeamIdentifier=L644Y3WX5T

$ spctl --assess --type execute -vv "build/Daily Challenge.app"   # before notarization, as expected
build/Daily Challenge.app: rejected
source=Unnotarized Developer ID
origin=Developer ID Application: Mykola Yakovetskyi (L644Y3WX5T)
```

The hardened-runtime flag, secure timestamp, signed nested bundle and absence of `get-task-allow` meet Apple's notarization prerequisites.

## Hardened runtime compatibility (static review)

No entitlements file was added, because nothing in the app needs a hardened-runtime exception:

- **Keychain session:** the Supabase SDK's `KeychainLocalStorage(service: "app.daily-challenge.proof.auth")` uses `kSecClassGenericPassword` with service/account attributes, no access group and no data-protection keychain, so it needs no entitlement. The identifiers in `HANDOFF.md` are unchanged. Because the code identity changes from ad-hoc to Developer ID, macOS may ask once on the captain's Mac whether Daily Challenge may use its existing item (or the session may need one sign-in). Developer ID updates keep the same designated requirement (bundle ID + team), so later updates should not ask again.
- **Launch at login:** `SMAppService.mainApp` needs no entitlement. A Developer ID app should not need the Login Items approval that ad-hoc builds may need.
- **Water reminders:** local `UNUserNotificationCenter` notifications need no entitlement. Real delivery remains owner acceptance (see `notification-fixture-verification.md`).
- `otool -L` lists only `/System/Library` and `/usr/lib` libraries, so library validation is satisfied; `Sources` has no JIT, `dlopen`, camera, microphone, location, contacts, calendar, photos or Apple Events use.

Runtime behaviour of the signed app (Keychain prompt, login item, notifications) was not exercised here, because launching it would touch the real Keychain session; it is owner acceptance on first install.

## Notarization and stapling

Before the profile existed, the default build stopped after signing with `Notarization credential profile "dc-notary" is missing or invalid.` (`notarytool history` exit 69). Once the owner stored `dc-notary`, the full default build (`bash scripts/build-proof.sh`, no flags) exited 0. Apple took about 35 minutes for this first submission.

```
Submission ID received
  id: 3b86bf78-5665-4a8e-8d6a-95b490240431
Processing complete
  id: 3b86bf78-5665-4a8e-8d6a-95b490240431
  status: Accepted

$ xcrun stapler staple "build/Daily Challenge.app"
The staple and validate action worked!
$ xcrun stapler validate "build/Daily Challenge.app"
The validate action worked!

$ spctl --assess --type execute -vv "build/Daily Challenge.app"
build/Daily Challenge.app: accepted
source=Notarized Developer ID
origin=Developer ID Application: Mykola Yakovetskyi (L644Y3WX5T)

Built (Developer ID signed, notarized, stapled): build/Daily Challenge.app
Share: build/DailyChallenge.zip
```

`xcrun notarytool log 3b86bf78-… --keychain-profile dc-notary`: `Accepted`, "Ready for distribution", issues `None`. The temporary submit zip was removed.

`build/DailyChallenge.zip` (3.1 MB) was extracted to a scratch folder and checked again: `stapler validate` worked and `spctl` reported `accepted`, `source=Notarized Developer ID`, so the shared zip carries the stapled app. Nothing was uploaded anywhere except the Apple notary service.

# iPhone widgets Phase 2: coordinated storage evidence

10 October 2026. Phase 2 only: the phone uses coordinated App Group storage; there is no
extension, widget UI, intent, shared Keychain group or widget networking in this change.
`VERSION`, JSON schema, transport and default Mac storage identifiers are unchanged.

## Verification

Environment: Xcode 27.0 (27A266a), iPhone 17 device type, iOS 27.0
(`com.apple.CoreSimulator.SimRuntime.iOS-27-0`). All app/test data is synthetic, with temporary
roots and fixture Auth; no production Keychain, installed Mac app or real account is accessed.
Only the authorized public build configuration was copied into ignored `.env.local`.

Commands, from the repository root:

```bash
(cd iOS && xcodegen generate) # A: generated project + entitlement committed with YAML
swift test                   # B: default callers + opted-in seam + separate-process lock
xcodebuild test -project iOS/DailyChallenge.xcodeproj -scheme DailyChallenge \
  -destination 'platform=iOS Simulator,name=iPhone 17' # C
DEVICE='Daily Challenge Phase 2' CAPTURE_PHASE2_ONLY=1 CAPTURE_WAIT=8 bash iOS/scripts/capture-screenshots.sh
bash scripts/ios-archive.sh --check # E: unsigned Release packaging only, no upload
```

The capture simulator is an isolated iPhone 17 / iOS 27.0 simulator named
**Daily Challenge Phase 2** (`B9F74167-6AC7-458F-AEE1-A3A7A120627C`). The helper builds and
runs Debug fixtures, with separate synthetic old/private and shared roots. It does not open
production App Group data or Auth.

All commands passed. B discovered **185 shared tests** (including two new kit tests):
46 tracker-interface, 5 probe, 9 proof-auth, 63 sync-kit and 62 core tests. C discovered
**20 phone unit tests and 13 UI tests**, all passed with no skipped tests; the final Xcode
result bundle reports 33/33 passed on iPhone 17 / iOS 27.0. The regenerated project compiles
`PhoneSharedStoreTests.swift` into the existing hosted test target. E produced the unsigned
`app.daily-challenge.ios` Release archive at unchanged version **0.3.0 (3)** with bundled
public configuration and no Sparkle. The entitlement contains only the specified App Group,
with no shared Keychain entitlement. `git diff --check` also passed.

All four final screenshots were visually inspected. The first Dark recovery capture caught
the launch screen; it was replaced by the final capture using an eight-second settling delay.
Today is unchanged and the recovery explanation/buttons are readable in both appearances.

## Storage acceptance coverage

- Two independent repository accessors log 40 concurrent pours and 40 habit toggles without
  losing events or pending IDs. A stale app adds a further pour, then undoes the latest
  committed custom pour. Pending IDs and history remain intact on offline relaunch.
- App toggles read committed habit/extra state; extra management, imports/previews/exports
  and reload use fresh loads. Archived extras reject new ticks/rename; stale undo with no
  pour creates no event/error. Existing correction locks and extras rules still pass.
- A separate Python process holds the same stable lock used by the phone repository;
  the Swift accessor waits until release. Same-process accessors also serialize. Network
  awaits run outside the lock: a second accessor edits during upload, and the fresh sync
  merge retains those events. An upload response without fetched IDs leaves events pending.
- Session/account changes invalidate metadata under the lock. Stale generations cannot write
  after sign-out or switch. A sign-out racing an action permits only the action that wins
  the lock first. Dormant history/queues remain isolated for subsequent sign-in; signed-out
  relaunch clears prior visibility even when the model initially has no owner.
- Missing container access, unavailable/protected data and corrupt history refuse reads or
  expose recovery, never a private fallback or empty setup. Failed account opens publish
  no cached account/title metadata. Metadata selects only its published owner/challenge.
- Relocation preserves original bytes, device IDs, challenge/event identities, queues,
  recovery backups and celebration files. Full staging validates before destination writes;
  copies are flushed before completion. Interruption retries same-content copies. Legacy
  migration retries retain the staged generated identity. Differing destinations, changed
  originals during recovery and corrupt sources stop without overwriting either root.
- The populated phone fixture before/after relocation compares water, habits, diet, extras,
  completion, current/best streak, milestones, challenge identity and pending event IDs.
  Foreground reload then exposes a second accessor's new pour. Preferences remain local.

## Simulator screenshots

These are captures of the running phone app, not in-process renders. Each uses the fixed
9 October 2026 Jersey fixture clock and synthetic account/history. Light and Dark pairs:

| Screen | Files |
| --- | --- |
| Today after relocation: 2,250 ml, Day 12, six-day current streak | [Light](screenshots/ios/sharedToday-light.png), [Dark](screenshots/ios/sharedToday-dark.png) |
| Two valid conflicting histories: readable recovery message, Try again, no setup | [Light](screenshots/ios/storageRecovery-light.png), [Dark](screenshots/ios/storageRecovery-dark.png) |

## Owner acceptance boundaries

Register/enable `group.app.daily-challenge.ios` on team `L644Y3WX5T` and associate it with
`app.daily-challenge.ios` before signed-device acceptance. Automatic signing may provision
profiles, but this unsigned archive proves neither registration nor entitlement authorization.
Phase 3 will separately associate the extension. No upload or team/account administration
was performed here.

Shared files explicitly use `completeUntilFirstUserAuthentication`. Tests inject unavailable
storage and require the calm refusal path. Simulator filesystems may omit Data Protection
attributes; actual protection before the first device unlock and usable signed App Group
access remain owner/device acceptance, not a claimed simulator result. Widget placeholders
and privacy-sensitive content belong to Phase 3, which remains unimplemented.

# Native notification fixture probe

## Result: authorization refused; delivery unverified

On macOS 27.0.1 (26A434), the isolated ad-hoc-signed fixture returned:

```text
fixture bundle: app.daily-challenge.notification-fixture.r1
initial authorization status: 0
authorization granted: false; error: Optional(Error Domain=UNErrorDomain Code=1 "Notifications are not allowed for this application" UserInfo={NSLocalizedDescription=Notifications are not allowed for this application})
```

Authorization status 0 is not determined. Native authorization then failed with
`UNErrorDomain` code 1. No delivery request was submitted, so actual delivery is
**not verified**. This establishes refusal for this fixture on this machine; it
does not establish whether signing, device policy, or another OS restriction is
the root cause. Do not claim that ad-hoc notification delivery works or that a
particular signing change would fix it.

The probe used `scripts/test-notification-fixture.sh`, which builds a standalone
AppKit/UserNotifications application under `build/notification-fixture/` with a
distinct bundle ID and visible FIXTURE label. It contains no tracker, auth,
network, Keychain, or production data access. It requests native authorization;
only if granted does it submit one explicitly labelled notification that requests
no water action. It records results in that build directory and exits. No macOS
settings, signing/security controls, running production app, or hosted services
were changed.

### Bounded GUI-launch diagnostic

Firstmate authorized one additional diagnostic and implementation with truthful
permission reporting, without pursuing signing/distribution changes. The fixture
was kept at the stable ignored worktree path
`build/notification-fixture/Daily Challenge Notification FIXTURE.app`, given the
complete app metadata, ad-hoc signed, verified with `codesign --verify --strict`,
registered with `lsregister -f`, and launched through `open -n -W` (not direct
binary execution). GUI stdout again reported exactly the refusal above: status
0, authorization false, `UNErrorDomain` code 1. No delivery request was submitted.
No permission prompt was clicked or OS settings changed. No further signing or
permission workaround was attempted.

Reminders are implemented with the actual permission state shown in Account.
They remain opt-in and do not claim to work when permission is denied or not
determined. **Native delivery on this ad-hoc configuration is unverified.** The
captain must accept using the real app; any PR must carry this limitation. See
[owner checks](water-reminders.md#owner-acceptance) rather than treating successful
fake-centre tests as proof of native delivery.

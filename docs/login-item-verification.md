# Launch-at-login verification

## Isolated checks (8 October 2026)

`swift test` passed: 85 tests across the package, including four fake-service login-item tests. These cover explicit on/off, initialization/refresh without registration, pending approval cancellation and external approval, missing bundle status, register/unregister failures and recovery. No real account, Keychain or challenge files are used.

`bash scripts/test-login-item-fixture.sh` compiled the production service adapter into an independent ad-hoc-signed **Daily Challenge Login FIXTURE.app**, bundle ID `app.daily-challenge.login-fixture`, under this disposable worktree's `build/login-item-fixture/`. On macOS 27.0.1 (26A434), the native service returned:

```text
Before: 3 (notFound)
After register: 1 (enabled)
After unregister: 0 (notRegistered)
```

Cleanup succeeded: the fixture was unregistered. The probe never launched or registered the real Daily Challenge app, read its records/session, or changed approval/security settings. This is registration evidence, not an actual logout/login launch test. The script is explicit opt-in integration tooling, not part of the automated test suite; it briefly registers only its fixture and always attempts unregistration even after a registration error. A cleanup failure exits nonzero and must be resolved before considering the probe complete.

## Owner acceptance on each permitted Mac

1. Use the intended installed bundle. In Account, confirm launch at login is off before opting in (unless already enabled through macOS). Merely opening Account or relaunching must not register it.
2. Toggle on. Confirm the actual state is enabled, or follow the displayed approval guidance in System Settings > General > Login Items. Ad-hoc signing may require approval. Never bypass company restrictions or disable security controls.
3. After approval, return to the app and confirm status refreshes. At the next normal login, verify the menu-bar app starts and existing data is retained. Automated checks do not perform logout/login.
4. Toggle off; confirm off in the app and no launch at the next normal login. Pending approval can also be cancelled with the switch.
5. The registration points to the current app bundle location, currently the captain's build folder. After moving or rebuilding to a different location, re-toggle off/on from the intended bundle. This feature does not install or relocate the app.

The choice is device-local, independent of sign-in and sync. No persisted Boolean is used to claim that registration succeeded. Requires-approval is displayed separately from enabled even though both keep the switch on so the request can be removed.

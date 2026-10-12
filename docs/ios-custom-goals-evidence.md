# iPhone custom daily goals and repeating extras: evidence (12 October)

Phases P2 (show each day's targets), P4 (Setup rows and editors, Account › Daily goals, Activity entries, the unmigrated-server message) and P5 (repeat picker and captions) on the iPhone app, widgets and intents. Behaviour: [iPhone daily goals](tracker-interface.md#custom-daily-goals-and-repeating-extras-on-the-iphone). **Simulator and fixtures only:** an iPhone 17 / iOS 27.0 simulator created for this work, Debug `-fixture` launches and fake transports. No real account, sign-in, hosted data, migration, real device or App Store Connect was used, and no installed app was touched.

## Automated checks

| Suite | Result |
| --- | --- |
| `swift test` (shared rules, sync kit, Mac interface) | 245 tests pass. The shared model, store and transport pieces are the Mac branch's, with its `DailyGoalsModelTests` and `serverWithoutTheGoalsUpdateRefusesGoalChangesClearlyAndKeepsThemPending`; this branch adds `TargetsFromTodayTests` (changes from today with earlier days kept, + pours the day's glass and a past day's own glass, a refused change writes nothing, schedules from today) and a custom-goal case in `MotionTests` |
| iPhone unit tests (`DailyChallengeTests`) | 57 pass (50 Swift Testing, 7 XCTest). New: `PhoneGoalsTests` (every preset valid and the slot's own preset equal to the standard target, amounts, icons and unknown-icon fallback, repeat captions, Activity wording by the day's targets, custom-goal and recurring fixtures, unmigrated server), `WidgetRenderTests` custom-goal, long-name and recurring variants |
| iPhone UI tests | `GoalsUITests` 7 pass (standard five accepted in one tap; Setup editors change Walk to Yoga and the glass to 330 ml before starting, then Today and + follow; amount, name and glass limits refuse with messages and disable Done; Daily goals changes the glass from today; custom goals on Today and the standard goal on an earlier History day; the unmigrated notice; the repeat picker). `TodayScreenUITests` 8 pass unchanged. Under the `WidgetCapture` scheme: `testWidgetActionsOffline`, `testPhase5LockScreen` and `testWidgetTapMapping` (with `WIDGET_PLACE=1`) pass on placed widgets |

```bash
swift test
xcodebuild test -project iOS/DailyChallenge.xcodeproj -scheme DailyChallenge \
  -destination 'platform=iOS Simulator,name=iPhone 17'
DEVICE="iPhone 17" CAPTURE_GOALS_ONLY=1 bash iOS/scripts/capture-screenshots.sh
```

## Captures (`docs/screenshots/ios/`, Light and Dark)

Real app on the simulator (`capture-screenshots.sh CAPTURE_GOALS_ONLY=1`):

- Setup: `goals-setup`, editors `goals-setup-water`, `goals-setup-walk`, `goals-setup-diet`, `goals-setup-reading`; large text `goals-setup-large-text`, `goals-editor-large-text`.
- Custom goals (Gym, Yoga, No sugar, Audiobook, 3,000 ml in 330 ml glasses, changed today): `goals-today`, `goals-today-large-text`, `goals-history-today` (Activity entries), `goals-history-before` (two days earlier, standard targets), `goals-account`, `goals-daily`, `goals-daily-walk`, `goals-unmigrated` (server without the update).
- Repeating extras: `goals-recurring-today`, `goals-recurring-large-text`, `goals-manage-extras`, `goals-repeat`.
- Recaptured because the screens changed: `setup`, `account`, `accountExtras`, `account-delete-row`, `account-extras-large-text`, `manage-extras`, `manage-extras-empty`, `manage-extras-cap`, `manage-extras-large-text`, `manage-extras-actions-large-text`.

In-process widget renders (`WidgetRenderTests` attachments; no SpringBoard compositor, tint or vibrancy): `goals-widget-requirements-medium-custom-goals`, `goals-widget-requirements-medium-long-goals` (20-character names shrink, then truncate; VoiceOver reads them whole), `goals-widget-water-small-custom-goals`, `goals-widget-water-medium-custom-goals`, `goals-widget-extras-medium-recurring`, `goals-widget-extras-large-recurring`.

## Only the owner can check

- **Apply `20261012000100_custom_targets_action_kinds.sql` before releasing this build** ([owner step](production-sync.md#custom-goals-update-owner-only-once)). Until then a goal or repeat change stays on the phone with the message shown in `goals-unmigrated`, and holds the other entries of its upload batch.
- On a real iPhone with a disposable account: set goals in Setup and in Daily goals, check the Mac and Android show them once their builds have the readers, and that iPhone 1.0 skips the rows and keeps syncing.
- Placed widgets on a real Home Screen with custom names (the long-name truncation is from in-process renders only), and VoiceOver on the editors.
- App Store listing, What's New and review notes ("+ glass", Account › Daily goals) are phase P6.

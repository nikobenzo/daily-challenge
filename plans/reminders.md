# Water Reminders

## Agreed behavior

Water notifications only. Default interval: 90 minutes, configurable. Default active window: 09:00–21:00 in Europe/Jersey. Enable on one chosen Mac initially, configurable independently on each device. Reminder enablement is device-local, not a shared switch that unexpectedly enables both Macs.

Stop reminders for a day once the locally known total meets 4,000 ml. If a correction makes today incomplete again, resume eligible future reminders; do not immediately deliver accumulated ones. No catch-up burst after sleep or relaunch. Do not notify outside the active window.

## Scheduling

Use native notification authorization and bounded upcoming schedules. The implemented anchoring, eligible slots, target-day eligibility and scheduling bounds are defined in [the scheduling reference](../docs/water-reminders.md#scheduling-and-limits). Reconcile pending notifications after edits, sync, wake, day changes, and settings changes. Do not promise delivery when macOS notification permission, Focus, or system scheduling prevents it.

If both Macs are enabled, duplicate reminders are possible. If the reminding Mac is offline, a goal achieved on the other Mac cannot instantly cancel its notifications. Avoid claiming exactly-once cross-device notification delivery.

## Acceptance

Test permission granted/denied, interval/window changes, completion cancellation, undo below target, midnight and DST, sleep/wake without a burst, and incoming synced completion. No notifications for workout, walk, diet, or reading. Notification wording should not encourage drinking beyond the target.

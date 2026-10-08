# Streaks and History

## Calendar rules

Use the IANA timezone Europe/Jersey on both Macs, regardless of the device's current timezone. A day runs between local midnights, including daylight-saving changes; do not model it as an invariant 24 hours.

The user selects a start date during setup. Earlier dates are outside the challenge. Historical tracked days require explicit records; a missing closed tracked date is missed, not implicitly complete. Future dates cannot be completed.

## Completion and current streak

A day is complete only when water is at least 4,000 ml, workout is complete, walk is complete, diet is clean, and Bible reading is complete.

Compute the consecutive complete sequence ending yesterday. If yesterday is missed, that base is zero. Add today if today is complete. Pending or explicitly missed today does not break the base until today's closing midnight. On the start date there is no prior base.

Examples:

- Yesterday ends a 12-day sequence, today pending: current streak 12.
- All today's requirements become complete: 13.
- Undo today's ninth standard pour: 12.
- Today closes unfinished: next day's streak is zero.
- Next day completes: one.
- App stays closed for several days: on next open, missing closed dates break the sequence.

Recompute on launch, day boundary, wake, edits, import, and sync. Midnight does not depend on the app being open to determine historical outcomes.

## History and milestones

Show a compact calendar with complete, missed, and in-progress states. Distinguish dates outside the challenge and future dates. Selecting a tracked date opens water entries and the four other requirements for correction.

Preserve underlying activity and correction history. Derive best streak and valid 75-day milestones from the current corrected history. A correction can invalidate a previously qualifying milestone; preserve the audit record, but do not display it as currently valid. Continue beyond 75 rather than ending or resetting the challenge.

A daily celebration follows an in-app completion transition, not popup opening. Track presentation separately from completion so reopening or toggling a habit does not repeatedly celebrate the same day. Historical corrections and incoming sync must not flood the user with old celebrations.

## Acceptance tests

Cover first tracked day, unrecorded dates, multiple missed days, future/outside dates, Jersey DST boundaries, device timezone changes, midnight while open, sleep through midnight, and launch after a gap. Verify restoration and invalidation of current/best streaks and milestones after corrections. Test streaks longer than 75 and water completion undone after other requirements are complete.

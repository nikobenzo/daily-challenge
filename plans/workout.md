# Workout

## Agreed behavior

At least 45 minutes of a qualifying workout every day. Home and gym workouts both qualify. No rest-day exemption. Completion is self-certified through a one-tap control; there is no timer or workout log in this release.

An unmarked workout remains pending. Marking it complete contributes to the day; reversing the mark makes it pending again. An unconfirmed closed day fails the challenge. History permits explicit corrections.

## Interface

One compact, accessible workout icon underneath the jug, with distinct pending and complete states. Provide a tooltip/accessibility description explaining the 45-minute requirement. Do not rely on color alone.

## Acceptance

- Completion can be toggled and corrected on a past day.
- Workout completion alone never completes the whole day.
- Reversal recalculates today's contribution or a historical streak.
- Latest explicit edit wins after sync under the shared conflict rules.
- No workout reminders, activity integrations, or duration tracking.

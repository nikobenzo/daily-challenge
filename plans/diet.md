# Diet

## Agreed behavior

Diet is self-certified, with three states: pending, clean, and missed. Clean satisfies the requirement; pending and missed do not. An unconfirmed closed day fails the challenge.

Written diet rules are optional and can be added later. Do not block setup or challenge completion on providing text. Do not invent restrictions on alcohol, sweets, takeaway, calories, or particular foods.

## Interface

A compact diet icon gives quick access to marking clean, marking missed, or returning to pending. Keep the normal completion action one tap; expose the explicit missed state without ambiguous cycling. Final interaction should be checked in the functional UI milestone.

## Rules text

Provide optional editable personal-rules text in settings. Proposed persistence: keep dated revisions for reference rather than overwriting the meaning of earlier records. Editing text does not automatically reclassify days; the user's explicit status remains authoritative.

## Acceptance

- Empty rules text is valid.
- Only clean contributes to completion.
- Marking today missed makes today incomplete, but does not prematurely erase yesterday's streak.
- Past clean/missed corrections recalculate streaks.
- No calorie tracker, food logging, automated enforcement, or diet reminders.

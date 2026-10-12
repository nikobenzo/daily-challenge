# Personal Challenge

A personal daily challenge combining water, two activities, diet, and reading (by default a workout, a walk and Bible reading). Success requires every requirement to be met on the same challenge day.

## Language

**Challenge day**:
A calendar date in the challenge's own timezone, bounded by local midnights, including daylight-saving changes.
_Avoid_: Rolling 24-hour window, fixed GMT day, the device's current timezone

**Challenge timezone**:
The IANA timezone (such as Europe/Jersey or America/New_York) chosen at setup whose midnights bound every challenge day. Like the start date, it cannot change after the challenge starts. Challenges started before timezones were chosen use Europe/Jersey.
_Avoid_: Device timezone (it only pre-fills the setup choice)

**Tracked day**:
A challenge day on or after the selected start date and no later than today.

**Daily requirements**:
Water, two activities, diet, and reading, each with the target in force on that challenge day. The standard targets are 4,000 ml of water, a 45-minute workout, a 45-minute walk, clean diet, and 10 Bible pages read. There are always exactly five.
_Avoid_: Sixth requirement, rest day

**Target**:
What one daily requirement asks for on a challenge day: water's daily goal and glass size, or a slot's name with an optional amount and unit (such as Yoga, 30 minutes). Amounts are shown, never measured: an activity is still met by its self-certified tick, and diet by a clean day.
_Avoid_: Custom habit, timer

**Target change**:
A dated change to one target that applies from its challenge day onward. Earlier days keep the targets they had, so a change never re-judges a past day or resets a streak. Changes are made for today; targets chosen at setup apply from the start day.
_Avoid_: Editing past goals

**Glass size**:
What the + button pours: 50 to 1,000 ml and no more than the daily goal, 450 ml unless changed.

**Pour**:
An individual logged water serving: a glass, or any other amount entered.
_Avoid_: Gallon, glass count

**Complete day**:
A tracked day on which all five daily requirements are met.

**Closed day**:
A challenge day whose ending midnight has passed.

**Missed day**:
A closed tracked day with at least one unmet or unconfirmed requirement.

**Current streak**:
Consecutive complete days ending yesterday, extended to today if today is complete. A missed closed day breaks this sequence.

**Best streak**:
The longest consecutive sequence of complete days in the current corrected history.

**75-day milestone**:
A run reaching 75 consecutive complete days; tracking continues afterward.

**Correction**:
An explicit change to recorded activity or status, including a past day, that can change completion and streaks.

**Clean diet**:
The user's self-certified compliance with their own diet rules for a challenge day; writing those rules is optional.

**Extra**:
A personal item beside the five daily requirements. It never counts toward a complete day or a streak. A one-off extra is a to-do: it carries over, marked late, until it is done or archived.

**Recurring extra**:
An extra scheduled to show on chosen weekdays, or every N days counted from the day the rule was set. It is never late and never carries over; each scheduled day is ticked on its own.

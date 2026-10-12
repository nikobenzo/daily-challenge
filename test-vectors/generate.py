#!/usr/bin/env python3
"""Writes challenge-rules.json: rule, merge and wire-format cases that both the Swift tests
(Tests/ChallengeCoreTests/ParityVectorTests.swift) and the Android tests
(android/core/src/test/.../ParityVectorTest.kt) run, so the clients cannot drift apart.

The expected values are the Swift tests' own assertions; the Swift run proves them against
ChallengeCore, the Kotlin run proves the Android port agrees. Regenerate with
`python3 test-vectors/generate.py` after adding a case, then run both test suites.
"""
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

REF = 978307200
JERSEY = "Europe/Jersey"
_counter = 0


def uid():
    global _counter
    _counter += 1
    return f"00000000-0000-4000-8000-{_counter:012X}"


def ref(iso):
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp() - REF


def iso(reference):
    return datetime.fromtimestamp(reference + REF, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def local(zone, y, m, d, h=12, mi=0, s=0):
    """Wall-clock time in a zone; an overflowing day rolls into the next month, as in Swift."""
    date = datetime(y, m, 1) + timedelta(days=d - 1)
    return iso(datetime(date.year, date.month, date.day, h, mi, s, tzinfo=ZoneInfo(zone)).timestamp() - REF)


def plus(instant, seconds):
    return iso(ref(instant) + seconds)


def day_start(zone, instant):
    moment = datetime.fromtimestamp(ref(instant) + REF, ZoneInfo(zone))
    return iso(datetime(moment.year, moment.month, moment.day, tzinfo=ZoneInfo(zone)).timestamp() - REF)


# Actions in their wire form.
def pour(ml): return {"pour": {"_0": ml}}
UNDO = {"undoLatestPour": {}}
def habit(name, done=True): return {"setHabit": {"_0": name, "completed": done}}
def diet(state): return {"setDiet": {"_0": state}}
def define(extra, title): return {"defineExtra": {"id": extra, "title": title}}
def archive(extra): return {"archiveExtra": {"id": extra}}
def tick(extra, done=True): return {"setExtra": {"id": extra, "completed": done}}
def target(slot, name, amount=None, unit=None, icon=None):
    value = {"_0": slot, "name": name}
    if amount is not None: value |= {"amount": amount, "unit": unit}
    if icon is not None: value["icon"] = icon
    return {"setTarget": value}
def water(goal, glass): return {"setWater": {"goal": goal, "pour": glass}}
def schedule(extra, weekdays=None, every=None):
    value = {"id": extra}
    if weekdays is not None: value["weekdays"] = weekdays
    if every is not None: value["every"] = every
    return {"scheduleExtra": value}


# A summary's expected targets: {"water": {...}} and slot -> {...}, every field given.
def slot(name, amount=None, unit=None, icon=None): return {"name": name, "amount": amount, "unit": unit, "icon": icon}
def goal(goal, glass): return {"goal": goal, "glass": glass}
STANDARD = {"water": goal(4000, 450), "workout": slot("Workout", 45, "minutes"), "walk": slot("Walk", 45, "minutes"),
            "diet": slot("Diet"), "bibleReading": slot("Bible", 10, "pages")}
HABITS = ["workout", "walk", "bibleReading"]


def record(action, on, at=None, device=None, id=None, returns="id", error=None):
    step = {"op": "record", "action": action, "on": on, "at": at or on, "id": id or uid()}
    if device: step["device"] = device
    if error: step["error"] = error
    elif returns is None: step["returns"] = None
    return step


def complete(on, at):
    return [record(pour(4000), on, at)] + [record(habit(h), on, at) for h in HABITS] + [record(diet("clean"), on, at)]


def activity(id, day, at, action, device, undone=None):
    """A wire activity; `day` is the start of the event's day, `at` its recorded time."""
    value = {"id": id, "day": ref(day), "recordedAt": ref(at), "action": action}
    if undone: value["undonePourID"] = undone
    if device is not None: value["deviceID"] = device
    for key in ("day", "recordedAt"):
        if value[key] == int(value[key]): value[key] = int(value[key])
    return value


def merge(events, error=None):
    step = {"op": "merge", "events": events}
    if error: step["error"] = error
    return step


def summary(on, as_of=None, **expect):
    return {"op": "summary", "on": on, "asOf": as_of or on, **expect}


def streaks(as_of, current, best=None, milestones=None):
    step = {"op": "streaks", "asOf": as_of, "current": current}
    if best is not None: step["best"] = best
    if milestones is not None: step["milestones"] = milestones
    return step


def case(name, start, steps, zone=JERSEY):
    return {"name": name, "timeZone": zone, "owner": "6F1C2A43-0B55-4B5E-9F3D-2C1A7E9B4D10", "start": start, "steps": steps}


cases = []
NOW = "2026-10-08T12:00:00Z"

# ChallengeTests
cases.append(case("nine standard pours reach four litres without clamping", NOW,
    [record(pour(450), NOW) for _ in range(8)]
    + [summary(NOW, water=3600, waterComplete=False), record(pour(450), NOW), summary(NOW, water=4050, waterComplete=True)]))

p1, p2, u = uid(), uid(), uid()
cases.append(case("undo removes the latest active pour and keeps correction history", NOW, [
    record(UNDO, NOW, returns=None),
    record(pour(3600), NOW, id=p1), record(pour(450), NOW, id=p2), record(UNDO, NOW, id=u),
    summary(NOW, water=3600, waterComplete=False, pours=[p1]),
    {"op": "history", "on": NOW, "ids": [p1, p2, u], "undone": {u: p2}},
]))

steps = [record(pour(4000), NOW)] + [record(habit(h), NOW) for h in HABITS]
steps += [summary(NOW, complete=False), record(diet("clean"), NOW), summary(NOW, complete=True, status="complete"),
          record(habit("bibleReading", False), NOW), summary(NOW, complete=False, habits=["workout", "walk"]),
          record(habit("bibleReading"), NOW), record(diet("missed"), NOW), summary(NOW, complete=False, diet="missed"),
          record(diet("pending"), NOW), summary(NOW, diet="pending")]
cases.append(case("all five requirements must be met and can be reversed", NOW, steps))

first = uid()
cases.append(case("invalid water amounts do not change the day", NOW, [
    record(pour(450), NOW, id=first),
    record(pour(0), NOW, error="invalidWaterAmount"), record(pour(-1), NOW, error="invalidWaterAmount"),
    summary(NOW, water=450), {"op": "history", "on": NOW, "ids": [first]},
]))

cases.append(case("dates outside tracking cannot be completed", NOW, [
    record(pour(450), "2026-10-07T12:00:00Z", NOW, error="dateOutsideChallenge"),
    record(pour(450), "2026-10-09T12:00:00Z", NOW, error="dateOutsideChallenge"),
    {"op": "history", "on": "2026-10-07T12:00:00Z", "ids": []},
]))

cases.append(case("an unfinished day closes at Jersey midnight rather than UTC midnight", NOW, [
    record(pour(450), NOW, "2026-10-08T22:59:59Z"),
    summary(NOW, "2026-10-08T22:59:59Z", status="inProgress"),
    summary(NOW, "2026-10-08T23:00:00Z", status="missed"),
    summary("2026-10-08T23:00:00Z", "2026-10-08T22:59:59Z", status="future"),
    summary("2026-10-08T23:00:00Z", "2026-10-08T23:00:00Z", status="inProgress"),
    summary("2026-10-07T12:00:00Z", "2026-10-08T23:00:00Z", status="outsideChallenge"),
]))

FIRST, YESTERDAY, TODAY, TOMORROW = "2026-10-06T12:00:00Z", "2026-10-07T12:00:00Z", NOW, "2026-10-09T12:00:00Z"
cases.append(case("today extends the streak but only a closed missed day resets it", FIRST,
    complete(FIRST, TODAY) + complete(YESTERDAY, TODAY) + [streaks(TODAY, 2)] + complete(TODAY, TODAY)
    + [streaks(TODAY, 3), record(UNDO, TODAY), streaks(TODAY, 2), streaks(TOMORROW, 0)]
    + complete(TOMORROW, TOMORROW) + [streaks(TOMORROW, 1, best=2)]))

for date, duration in [("2026-03-29T12:00:00Z", 82800), ("2026-10-25T12:00:00Z", 90000)]:
    cases.append(case(f"Jersey day interval on {date[:10]} respects daylight saving", date,
        [summary(date, intervalDuration=duration)]))

start, now = "2026-01-01T12:00:00Z", "2026-03-17T12:00:00Z"
steps = []
for offset in range(76): steps += complete(plus(start, offset * 86400), now)
missed = "2026-01-10T12:00:00Z"
steps += [streaks(now, 76, best=76, milestones=["2026-03-16T00:00:00Z"]),
          record(diet("missed"), missed, now), streaks(now, 66, milestones=[]),
          record(diet("clean"), missed, now), streaks(now, 76, milestones=["2026-03-16T00:00:00Z"])]
cases.append(case("75-day milestones are recalculated without stopping tracking", start, steps))

firstID, undoID = uid(), uid()
cases.append(case("retrying the same undo does not undo a second pour", NOW, [
    record(pour(450), NOW, id=firstID), record(pour(450), NOW, id=firstID), record(pour(450), NOW),
    record(UNDO, NOW, id=undoID), record(UNDO, NOW, id=undoID),
    summary(NOW, water=450),
    record(pour(900), NOW, id=firstID, error="conflictingActivity"),
    summary(NOW, water=450),
]))

cases.append(case("overflowing water totals are rejected without changing history", NOW, [
    record(pour(9223372036854775807), NOW), record(pour(1), NOW, error="invalidWaterAmount"),
]))

FIRST5, MISSING = "2026-10-05T12:00:00Z", "2026-10-06T12:00:00Z"
cases.append(case("corrections fill historical gaps without changing today's water", FIRST5,
    complete(FIRST5, TODAY) + complete(YESTERDAY, TODAY) + complete(TODAY, TODAY)
    + [streaks(TODAY, 2), summary(MISSING, TODAY, status="missed")] + complete(MISSING, TODAY)
    + [streaks(TODAY, 4, best=4), summary(TODAY, water=4000)]))

cases.append(case("launch after an unrecorded gap finds missed days", "2026-10-01T12:00:00Z",
    complete("2026-10-01T12:00:00Z", "2026-10-01T12:00:00Z")
    + [streaks("2026-10-05T12:00:00Z", 0, best=1), summary("2026-10-04T12:00:00Z", "2026-10-05T12:00:00Z", status="missed")]))
cases.append(case("a challenge that has not started has no streak", "2026-10-06T12:00:00Z",
    [streaks("2026-10-05T12:00:00Z", 0, best=0)]))

cases.append(case("explicitly missed diet today does not erase yesterday's streak early", YESTERDAY,
    complete(YESTERDAY, YESTERDAY) + [record(diet("missed"), TODAY), streaks(TODAY, 1), streaks("2026-10-08T23:00:00Z", 0)]))

for dates in (["2026-03-28T12:00:00Z", "2026-03-29T12:00:00Z", "2026-03-30T12:00:00Z"],
              ["2026-10-24T12:00:00Z", "2026-10-25T12:00:00Z", "2026-10-26T12:00:00Z"]):
    steps = []
    for d in dates: steps += complete(d, dates[2])
    cases.append(case(f"streaks count calendar days across daylight saving ({dates[1][:10]})", dates[0],
        steps + [streaks(dates[2], 3, best=3)]))

# ChallengeTimeZoneTests, in each zone
ZONES = ["Europe/Jersey", "America/New_York", "Australia/Sydney", "GMT"]
for z in ZONES:
    s, before, midnight = local(z, 2026, 10, 8), local(z, 2026, 10, 8, 23, 59, 59), local(z, 2026, 10, 9, 0)
    cases.append(case(f"an unfinished day closes at the zone's midnight ({z})", s, [
        record(pour(450), s, before),
        summary(s, before, status="inProgress"), summary(s, midnight, status="missed"),
        summary(midnight, before, status="future"), summary(midnight, midnight, status="inProgress"),
        summary(local(z, 2026, 10, 7), midnight, status="outsideChallenge"), streaks(before, 0),
    ], zone=z))
    for h, mi in [(0, 10), (23, 30)]:
        picked = local(z, 2026, 10, 8, h, mi)
        cases.append(case(f"start dates normalize to the zone's midnight ({z} {h:02}:{mi:02})", picked, [
            {"op": "startDate", "equals": local(z, 2026, 10, 8, 0)},
            record(pour(450), local(z, 2026, 10, 7, 23, 59), picked, error="dateOutsideChallenge"),
        ], zone=z))
    st = local(z, 2026, 1, 1)
    now = local(z, 2026, 3, 17)
    steps = []
    for offset in range(76):
        y, m, d = (datetime(2026, 1, 1) + timedelta(days=offset)).timetuple()[:3]
        steps += complete(local(z, y, m, d), now)
    cases.append(case(f"75-day milestones fall on the zone's local day ({z})", st,
        steps + [streaks(now, 76, milestones=[local(z, 2026, 3, 16, 0)])], zone=z))

for z, y, m, d, duration in [("Europe/Jersey", 2026, 3, 29, 82800), ("Europe/Jersey", 2026, 10, 25, 90000),
                             ("America/New_York", 2026, 3, 8, 82800), ("America/New_York", 2026, 11, 1, 90000),
                             ("Australia/Sydney", 2026, 10, 4, 82800), ("Australia/Sydney", 2026, 4, 5, 90000),
                             ("GMT", 2026, 3, 29, 86400), ("GMT", 2026, 10, 25, 86400)]:
    date = local(z, y, m, d)
    cases.append(case(f"day interval in {z} on {y}-{m:02}-{d:02}", date,
        [summary(date, intervalDuration=duration, intervalStart=local(z, y, m, d, 0))], zone=z))

for z, y, m, d in [("Europe/Jersey", 2026, 3, 28), ("Europe/Jersey", 2026, 10, 24), ("America/New_York", 2026, 3, 7),
                   ("America/New_York", 2026, 10, 31), ("Australia/Sydney", 2026, 10, 3), ("Australia/Sydney", 2026, 4, 4),
                   ("GMT", 2026, 3, 28), ("GMT", 2026, 10, 24)]:
    days = [local(z, y, m, d + i) for i in range(3)]
    steps = []
    for day in days: steps += complete(day, days[2])
    missed_midnight = local(z, y, m, d + 4, 0)
    cases.append(case(f"streaks count the zone's calendar days across daylight saving ({z} {y}-{m:02}-{d:02})", days[0],
        steps + [streaks(days[2], 3), streaks(plus(missed_midnight, -1), 3), streaks(missed_midnight, 0, best=3)], zone=z))

moment = "2026-10-08T13:30:00Z"
for z, day, start in [("Australia/Sydney", local("Australia/Sydney", 2026, 10, 9, 0), "2026-10-08T13:00:00Z"),
                      ("Europe/Jersey", local("Europe/Jersey", 2026, 10, 8, 0), "2026-10-07T23:00:00Z")]:
    pid = uid()
    cases.append(case(f"the same instant is the zone's own calendar date ({z})", moment, [
        {"op": "startDate", "equals": start}, record(pour(450), moment, id=pid),
        {"op": "activityDays", "days": [day]},
    ], zone=z))

# ChallengeSyncTests (Challenge-level merge)
SYNC = iso(1791460800 - REF)  # 2026-10-08T12:00:00Z in Unix seconds
SYNC_DAY = day_start(JERSEY, SYNC)
older, skewed, deviceA = uid(), uid(), uid()
firstEdit, lastEdit = "00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000002"
events = [activity(older, SYNC_DAY, SYNC, habit("walk", False), "Z"),
          activity(skewed, SYNC_DAY, plus(SYNC, 86400), habit("walk"), "A"),
          activity(deviceA, SYNC_DAY, SYNC, diet("missed"), "A"),
          activity(firstEdit, SYNC_DAY, SYNC, diet("pending"), "B"),
          activity(lastEdit, SYNC_DAY, SYNC, diet("clean"), "B")]
order = [deviceA, firstEdit, lastEdit, older, skewed]
for name, batch in [("in order", events), ("reversed", list(reversed(events)))]:
    cases.append(case(f"conflicting habit edits use timestamp, device, then event ID ({name})", SYNC, [
        merge(batch), {"op": "activities", "ids": order},
        summary(SYNC, habits=["walk"], diet="clean"),
    ]))

pa, pb, ua, ub, p200, p300 = uid(), uid(), uid(), uid(), uid(), uid()
initial = [activity(pa, SYNC_DAY, SYNC, pour(450), "DEV-A"), activity(pb, SYNC_DAY, plus(SYNC, 1), pour(450), "DEV-A")]
later = [activity(ua, SYNC_DAY, plus(SYNC, 2), UNDO, "DEV-A", undone=pb),
         activity(ub, SYNC_DAY, plus(SYNC, 3), UNDO, "DEV-B", undone=pb),
         activity(p200, SYNC_DAY, plus(SYNC, 4), pour(200), "DEV-A"),
         activity(p300, SYNC_DAY, plus(SYNC, 5), pour(300), "DEV-B")]
for name, batches in [("forward", [initial, later]), ("reversed", [list(reversed(later + initial))]),
                      ("with duplicates and a stale replay", [initial, later + initial + later, initial])]:
    cases.append(case(f"two offline devices merge additions and a duplicate undo without resurrection ({name})", SYNC,
        [merge(b) for b in batches] + [summary(SYNC, water=950, pours=[pa, p200, p300]),
                                       {"op": "activities", "ids": [pa, pb, ua, ub, p200, p300]}]))

base = uid()
cases.append(case("merge rejects invalid events and keeps history", SYNC, [
    merge([activity(base, SYNC_DAY, SYNC, pour(450), "A")]),
    merge([activity(base, SYNC_DAY, SYNC, pour(900), "A")], error="conflictingActivity"),
    merge([activity(uid(), SYNC_DAY, SYNC, pour(0), "A")], error="invalidWaterAmount"),
    merge([activity(uid(), SYNC_DAY, SYNC, pour(450), "A", undone=base)], error="invalidWaterAmount"),
    merge([activity(uid(), SYNC_DAY, SYNC, UNDO, "A")], error="conflictingActivity"),
    merge([activity(uid(), SYNC_DAY, SYNC, UNDO, "A", undone=uid())], error="conflictingActivity"),
    merge([activity(uid(), SYNC_DAY, SYNC, habit("walk"), "A", undone=base)], error="conflictingActivity"),
    merge([activity(uid(), SYNC, SYNC, pour(450), "A")], error="dateOutsideChallenge"),
    merge([activity(uid(), plus(SYNC_DAY, -86400), SYNC, pour(450), "A")], error="dateOutsideChallenge"),
    merge([activity(uid(), plus(SYNC_DAY, 86400), SYNC, pour(450), "A")], error="dateOutsideChallenge"),
    merge([activity(uid(), SYNC_DAY, SYNC, pour(9223372036854775807), "A")], error="invalidWaterAmount"),
    {"op": "activities", "ids": [base]}, summary(SYNC, water=450),
]))
# An undo of a pour on another day.
other = uid()
NEXT = plus(SYNC, 86400)
cases.append(case("an undo must target a pour on its own day", SYNC, [
    merge([activity(other, SYNC_DAY, SYNC, pour(450), "A")]),
    merge([activity(uid(), day_start(JERSEY, NEXT), NEXT, UNDO, "A", undone=other)], error="conflictingActivity"),
]))

# ChallengeExtrasTests
DAY1 = iso(1791460800 - REF)
DAY2, DAY3, DAY4 = plus(DAY1, 86400), plus(DAY1, 2 * 86400), plus(DAY1, 3 * 86400)
D1, D2, D3 = (day_start(JERSEY, d) for d in (DAY1, DAY2, DAY3))

stretch, journal, read = uid(), uid(), uid()
initial = [activity(uid(), D1, DAY1, define(stretch, "Stretch"), "MAC-A"),
           activity(uid(), D1, plus(DAY1, 1), define(journal, "Journal"), "MAC-A")]
tickJournal = uid()
offline = [activity(uid(), D2, DAY2, define(stretch, "Stretch 10 min"), "MAC-A"),
           activity(uid(), D1, plus(DAY2, 1), tick(stretch), "MAC-A"),
           activity(uid(), D2, plus(DAY2, 2), archive(journal), "MAC-A"),
           activity(uid(), D2, plus(DAY2, 3), define(stretch, "Stretch 15 min"), "MAC-B"),
           activity(uid(), D2, plus(DAY2, 4), define(read, "Read"), "MAC-B"),
           activity(tickJournal, D2, plus(DAY2, 5), tick(journal), "MAC-B"),
           activity(uid(), D2, plus(DAY2, 6), tick(read), "MAC-B")]
checks = [
    {"op": "allExtras", "extras": [
        {"id": stretch, "title": "Stretch 15 min", "firstDay": D1, "completedOn": D1, "archivedFrom": None},
        {"id": journal, "title": "Journal", "firstDay": D1, "completedOn": None, "archivedFrom": D2},
        {"id": read, "title": "Read", "firstDay": D2, "completedOn": D2, "archivedFrom": None}]},
    {"op": "shownExtras", "asOf": DAY2, "ids": [read]},
    {"op": "shownExtras", "asOf": DAY1, "ids": [stretch, journal]},
    summary(DAY1, DAY2, completedExtras=[stretch], extrasDone=1, extrasTotal=2),
    summary(DAY2, DAY2, completedExtras=[read], extrasTotal=1),
]
for name, batches in [("forward", [initial, offline]), ("reversed", [list(reversed(offline + initial))])]:
    cases.append(case(f"two devices converge on define, rename, archive and ticks ({name})", DAY1,
        [merge(b) for b in batches] + checks))

pending, done = uid(), uid()
base_steps = complete(DAY1, DAY1)
cases.append(case("extras never change whether a day is complete", DAY1, base_steps + [
    record(define(pending, "Never ticked"), DAY1), record(define(done, "Ticked"), DAY1),
    record(tick(done), DAY1), record(tick(done), DAY2, DAY2), record(tick(pending), DAY2, DAY2),
    summary(DAY1, DAY2, complete=True, status="complete", allExtrasDone=False),
    summary(DAY2, DAY2, complete=False, status="inProgress", allExtrasDone=True),
    streaks(DAY2, 1, best=1, milestones=[]),
    record(archive(pending), DAY2, DAY2),
    summary(DAY1, DAY2, complete=True), summary(DAY2, DAY2, complete=False),
]))

known = uid()
stranger, late_id = uid(), uid()
steps = [record(pour(450), DAY1, device="MacA", id=known)]
steps += [merge([activity(uid(), D1, DAY1, tick(stranger), "MacB")], error="unknownExtra"),
          merge([activity(uid(), D1, DAY1, archive(stranger), "MacB")], error="unknownExtra")]
for title in ["", "   ", " Padded", "x" * 41, "Two\nlines", "Tab\there"]:
    steps.append(merge([activity(uid(), D1, DAY1, define(uid(), title), "MacB")], error="invalidExtraTitle"))
steps.append({"op": "activities", "ids": [known]})
tickID = uid()
steps += [merge([activity(tickID, D1, DAY1, tick(late_id), "MacB"),
                 activity(uid(), D1, plus(DAY1, 60), define(late_id, "é" * 40), "MacC")]),
          summary(DAY1, DAY1, completedExtras=[late_id])]
cases.append(case("merge rejects extras events for an undefined extra or an invalid title", DAY1, steps))

ids = [uid() for _ in range(10)]
steps = [record(define(uid(), " untrimmed"), DAY1, error="invalidExtraTitle"),
         record(tick(uid()), DAY1, error="unknownExtra")]
steps += [record(define(e, f"Extra {i}"), DAY1) for i, e in enumerate(ids)]
steps += [record(define(uid(), "Eleventh"), DAY1, error="tooManyExtras"),
          record(define(ids[0], "Renamed"), DAY1), record(tick(ids[1]), DAY1),
          record(archive(ids[1]), DAY2, DAY2), record(archive(ids[1]), DAY2, DAY2, returns=None),
          record(define(uid(), "Eleventh"), DAY2, DAY2),
          {"op": "shownExtrasCount", "asOf": DAY2, "count": 10},
          record(define(ids[1], "Back"), DAY2, DAY2, error="archivedExtra"),
          record(tick(ids[1], False), DAY2, DAY2, error="archivedExtra"),
          record(tick(ids[1], False), DAY1, DAY2),
          summary(DAY1, DAY2, completedExtras=[])]
cases.append(case("recording enforces the cap, titles and archived extras", DAY1, steps))

s, dentist, lunch = uid(), uid(), uid()
cases.append(case("an open extra carries over as late and a completed one leaves later days", DAY1, [
    record(define(s, "Stretch"), DAY1), record(define(dentist, "Book dentist"), DAY1), record(tick(s), DAY1),
    summary(DAY1, DAY4, extras=["Stretch ✓", "Book dentist"]),
    summary(DAY2, DAY4, extras=["Book dentist late"]),
    {"op": "shownExtras", "asOf": DAY2, "ids": [dentist]},
    record(define(lunch, "Prep lunch"), DAY3, DAY3), record(tick(dentist), DAY3, DAY3),
    summary(DAY2, DAY4, extras=["Book dentist late"]),
    summary(DAY3, DAY4, extras=["Book dentist ✓ late", "Prep lunch"]),
    summary(DAY3, DAY3, allExtrasDone=False),
    summary(DAY4, DAY4, extras=["Prep lunch late"]),
]))

e = uid()
cases.append(case("correcting a past day moves the completion and the carry-over", DAY1, [
    record(define(e, "Stretch"), DAY1), record(tick(e), DAY1), summary(DAY3, DAY3, extras=[]),
    record(tick(e, False), DAY1, DAY3),
    summary(DAY1, DAY3, extras=["Stretch"]), summary(DAY2, DAY3, extras=["Stretch late"]), summary(DAY3, DAY3, extras=["Stretch late"]),
    record(tick(e), DAY2, DAY3),
    summary(DAY1, DAY3, extras=["Stretch"]), summary(DAY2, DAY3, extras=["Stretch ✓ late"]), summary(DAY3, DAY3, extras=[]),
    record(define(e, "Stretch 10 min"), DAY3, DAY3),
    summary(DAY2, DAY3, extras=["Stretch 10 min ✓ late"]), summary(DAY3, DAY3, extras=[]),
]))

e = uid()
cases.append(case("archiving ends the carry-over and a tick from its archive day never completes it", DAY1, [
    record(define(e, "Journal"), DAY1, device="MacA"), record(archive(e), DAY3, DAY3, device="MacA"),
    merge([activity(uid(), D3, DAY3, tick(e), "MacB")]),
    summary(DAY1, DAY4, extras=["Journal"]), summary(DAY2, DAY4, extras=["Journal late"]),
    summary(DAY3, DAY4, extras=[]), summary(DAY4, DAY4, extras=[]),
    {"op": "allExtras", "extras": [{"id": e, "title": "Journal", "firstDay": D1, "completedOn": None, "archivedFrom": D3}]},
    {"op": "openExtras", "asOf": DAY3, "ids": []},
]))

daily, never = uid(), uid()
recorded = [record(define(daily, "Stretch"), DAY2, DAY2, device="MacA"), record(define(never, "Journal"), DAY2, DAY2, device="MacA"),
            record(tick(daily), DAY1, DAY2, device="MacA"), record(tick(daily), DAY2, DAY2, device="MacA"),
            record(tick(daily), DAY3, DAY3, device="MacA")]
cases.append(case("histories recorded under the every-day rule render without rewriting", DAY1, recorded + [
    summary(DAY1, DAY4, extras=["Stretch ✓"]), summary(DAY2, DAY4, extras=["Journal"]), summary(DAY3, DAY4, extras=["Journal late"]),
    {"op": "allExtras", "extras": [
        {"id": daily, "title": "Stretch", "firstDay": D1, "completedOn": D1, "archivedFrom": None},
        {"id": never, "title": "Journal", "firstDay": D2, "completedOn": None, "archivedFrom": None}]},
]))

ids = [uid() for _ in range(10)]
steps = [record(define(e, f"Extra {i}"), DAY1) for i, e in enumerate(ids)]
steps += [record(define(uid(), "Eleventh"), DAY1, error="tooManyExtras"), record(tick(ids[0]), DAY1),
          {"op": "openExtrasCount", "asOf": DAY1, "count": 9}, record(define(uid(), "Eleventh"), DAY1),
          {"op": "shownExtrasCount", "asOf": DAY1, "count": 11}, {"op": "shownExtrasCount", "asOf": DAY2, "count": 10},
          record(tick(ids[0], False), DAY1), {"op": "openExtrasCount", "asOf": DAY1, "count": 11},
          record(define(uid(), "Twelfth"), DAY1, error="tooManyExtras")]
cases.append(case("the cap counts only open extras", DAY1, steps))

late_evening = local("Australia/Sydney", 2026, 10, 8, 23, 30)
past_midnight = plus(late_evening, 3600)
e = uid()
cases.append(case("the carry-over rolls at the challenge zone's midnight", late_evening, [
    record(define(e, "Stretch"), late_evening),
    summary(late_evening, late_evening, extras=["Stretch"]),
    summary(past_midnight, past_midnight, extras=["Stretch late"]),
], zone="Australia/Sydney"))

# Custom daily targets (custom goals plan, P1a): dated events, resolved per day.
DAY5, DAY6 = plus(DAY1, 4 * 86400), plus(DAY1, 5 * 86400)
D4, D5, D6 = (day_start(JERSEY, d) for d in (DAY4, DAY5, DAY6))


def glasses(count, on, at=None): return [record(pour(450), on, at) for _ in range(count)]


def complete_with(on, at, millilitres):
    return [record(pour(millilitres), on, at)] + [record(habit(h), on, at) for h in HABITS] + [record(diet("clean"), on, at)]


cases.append(case("without target events a day uses the standard five", DAY1, [
    summary(DAY1, targets=STANDARD), summary(DAY1, DAY3, targets=STANDARD),
] + glasses(8, DAY1) + [summary(DAY1, water=3600, waterComplete=False)]))

YOGA = target("walk", "Yoga", 30, "minutes", "yoga")
AUDIO = target("bibleReading", "Audiobook", 20, "minutes", "headphones")
custom = {"water": goal(3000, 250), "walk": slot("Yoga", 30, "minutes", "yoga"),
          "bibleReading": slot("Audiobook", 20, "minutes", "headphones"), "workout": STANDARD["workout"], "diet": STANDARD["diet"]}
cases.append(case("setup targets dated a past start day apply from that day", DAY1, [
    record(water(3000, 250), DAY1, DAY3), record(YOGA, DAY1, DAY3), record(AUDIO, DAY1, DAY3),
    summary(DAY1, DAY3, targets=custom), summary(DAY2, DAY3, targets=custom), summary(DAY3, DAY3, targets=custom),
] + glasses(7, DAY1, DAY3) + [
    summary(DAY1, DAY3, water=3150, waterComplete=True),
] + [record(habit(h), DAY1, DAY3) for h in HABITS] + [record(diet("clean"), DAY1, DAY3),
    summary(DAY1, DAY3, complete=True, status="complete"), streaks(DAY3, 0, best=1)]))

cases.append(case("a change from today leaves earlier days on their own targets", DAY1, [
    record(target("diet", "No sugar"), DAY2, DAY2), record(water(3000, 500), DAY2, DAY2),
    summary(DAY1, DAY2, targets=STANDARD),
    summary(DAY2, DAY2, targets=STANDARD | {"water": goal(3000, 500), "diet": slot("No sugar")}),
    summary(DAY3, DAY3, targets=STANDARD | {"water": goal(3000, 500), "diet": slot("No sugar")}),
] + glasses(7, DAY1, DAY2) + glasses(7, DAY2, DAY2) + [
    summary(DAY1, DAY2, water=3150, waterComplete=False), summary(DAY2, DAY2, water=3150, waterComplete=True),
]))

early, late_ = uid(), uid()
same_slot = [activity(early, D2, DAY2, target("walk", "Yoga"), "PHONE"),
             activity(late_, D2, plus(DAY2, 60), target("walk", "Pilates", 30, "minutes"), "MAC")]
tie = [activity(uid(), D2, plus(DAY2, 120), target("workout", "Run", 30, "minutes", "run"), "B-DEVICE"),
       activity(uid(), D2, plus(DAY2, 120), target("workout", "Swim", 30, "minutes", "swim"), "A-DEVICE")]
for name, batch in [("in order", same_slot + tie), ("reversed", list(reversed(same_slot + tie)))]:
    cases.append(case(f"two devices changing one slot on one day resolve by event order ({name})", DAY1, [
        merge(batch),
        summary(DAY2, DAY2, targets=STANDARD | {"walk": slot("Pilates", 30, "minutes"), "workout": slot("Run", 30, "minutes", "run")}),
        summary(DAY1, DAY2, targets=STANDARD),
    ]))

cases.append(case("two devices changing different slots both survive", DAY1, [
    merge([activity(uid(), D1, DAY1, target("walk", "Yoga"), "PHONE")]),
    merge([activity(uid(), D1, plus(DAY1, 1), water(2500, 330), "MAC"),
           activity(uid(), D1, plus(DAY1, 2), target("bibleReading", "Book", 2, "chapters", "book"), "MAC")]),
    summary(DAY1, targets=STANDARD | {"walk": slot("Yoga"), "water": goal(2500, 330),
                                      "bibleReading": slot("Book", 2, "chapters", "book")}),
]))

cases.append(case("the latest dated change wins even when an earlier-dated one is recorded later", DAY1, [
    record(water(3000, 250), DAY2, DAY2), record(water(2000, 250), DAY1, DAY3),
    record(target("walk", "Yoga"), DAY2, DAY2), record(target("walk", "Pilates"), DAY1, DAY3),
    summary(DAY1, DAY3, targets=STANDARD | {"water": goal(2000, 250), "walk": slot("Pilates")}),
    summary(DAY2, DAY3, targets=STANDARD | {"water": goal(3000, 250), "walk": slot("Yoga")}),
    summary(DAY3, DAY3, targets=STANDARD | {"water": goal(3000, 250), "walk": slot("Yoga")}),
]))

cases.append(case("lowering today's goal completes water and raising it un-completes today", DAY1,
    complete_with(DAY1, DAY1, 3150) + [
        summary(DAY1, waterComplete=False, status="inProgress"),
        record(water(3000, 250), DAY1), summary(DAY1, waterComplete=True, complete=True, status="complete"), streaks(DAY1, 1),
        record(water(3500, 250), DAY1), summary(DAY1, waterComplete=False, complete=False, status="inProgress"), streaks(DAY1, 0),
    ]))

cases.append(case("a streak runs across goal changes and each day keeps its own goal", DAY1,
    complete_with(DAY1, DAY4, 4000) + [record(water(3000, 250), DAY2, DAY2)] + complete_with(DAY2, DAY4, 3000)
    + [record(water(5000, 1000), DAY3, DAY3)] + complete_with(DAY3, DAY4, 5000) + complete_with(DAY4, DAY4, 4999) + [
        streaks(DAY4, 3, best=3), summary(DAY4, waterComplete=False),
        record(pour(1), DAY4), streaks(DAY4, 4, best=4, milestones=[]),
    ]))

cases.append(case("a correction on a past day is judged by that day's goal", DAY1, [
    record(water(3000, 250), DAY3, DAY3),
] + complete_with(DAY1, DAY3, 3150) + complete_with(DAY3, DAY3, 3150) + [
    summary(DAY1, DAY3, waterComplete=False, status="missed"), summary(DAY3, DAY3, waterComplete=True, status="complete"),
    record(pour(850), DAY1, DAY3), summary(DAY1, DAY3, water=4000, status="complete"),
]))

cases.append(case("recording refuses invalid targets and changes nothing", DAY1, [
    record(target("walk", "Yoga", 301, "minutes"), DAY1, error="invalidTarget"),
    record(target("walk", " Yoga"), DAY1, error="invalidTarget"),
    record(target("walk", "x" * 21), DAY1, error="invalidTarget"),
    record(target("diet", "No sugar", 1, "pages"), DAY1, error="invalidTarget"),
    record(target("walk", "Yoga", icon="Yoga"), DAY1, error="invalidTarget"),
    record({"setTarget": {"_0": "walk", "name": "Yoga", "amount": 30}}, DAY1, error="invalidTarget"),
    record(water(999, 250), DAY1, error="invalidTarget"), record(water(5001, 250), DAY1, error="invalidTarget"),
    record(water(3000, 49), DAY1, error="invalidTarget"), record(water(1000, 1001), DAY1, error="invalidTarget"),
    record(water(3000, 250), DAY2, DAY1, error="dateOutsideChallenge"),
    record(target("walk", "Yoga", icon="trampoline"), DAY1),
    record(target("walk", "x" * 20, 1000, "steps"), DAY1), record(water(1000, 1000), DAY1), record(water(5000, 50), DAY1),
    summary(DAY1, targets=STANDARD | {"walk": slot("x" * 20, 1000, "steps"), "water": goal(5000, 50)}),
]))

# Recurring extras (P1b): scheduleExtra sets the rule from its day; never late.
s1, s2 = uid(), uid()
cases.append(case("an extra repeating every day shows each day, ticked per day, never late", DAY1, [
    record(define(s1, "Stretch"), DAY1), record(schedule(s1, every=1), DAY1), record(define(s2, "Book dentist"), DAY1),
    summary(DAY1, DAY4, extras=["Stretch", "Book dentist"]),
    record(tick(s1), DAY2, DAY4), record(tick(s1), DAY3, DAY4),
    summary(DAY2, DAY4, extras=["Stretch ✓", "Book dentist late"], extrasDone=1, extrasTotal=2),
    summary(DAY3, DAY4, extras=["Stretch ✓", "Book dentist late"]), summary(DAY4, DAY4, extras=["Stretch", "Book dentist late"]),
    record(tick(s2), DAY4), record(tick(s1), DAY4), summary(DAY4, DAY4, extras=["Stretch ✓", "Book dentist ✓ late"], allExtrasDone=True),
    {"op": "openExtras", "asOf": DAY4, "ids": [s1]},
    {"op": "allExtras", "extras": [
        {"id": s1, "title": "Stretch", "firstDay": D1, "completedOn": None, "archivedFrom": None, "schedule": "every 1"},
        {"id": s2, "title": "Book dentist", "firstDay": D1, "completedOn": D4, "archivedFrom": None, "schedule": "once"}]},
    summary(DAY4, DAY4, complete=False),
]))

for z, y, m, d in [("Europe/Jersey", 2026, 10, 23), ("America/New_York", 2026, 10, 30), ("Australia/Sydney", 2026, 10, 2)]:
    e = uid()
    days = [local(z, y, m, d + i) for i in range(4)]  # a Friday, then Saturday to Monday across the change
    cases.append(case(f"a weekday extra follows the zone's calendar across daylight saving ({z})", days[0], [
        record(define(e, "Pack lunch"), days[0]), record(schedule(e, weekdays=[1, 2, 3, 4, 5]), days[0]),
        summary(days[0], days[3], extras=["Pack lunch"]), summary(days[1], days[3], extras=[]),
        summary(days[2], days[3], extras=[]), summary(days[3], days[3], extras=["Pack lunch"]),
        {"op": "openExtras", "asOf": days[2], "ids": [e]},
    ], zone=z))

e = uid()
cases.append(case("every N days counts from the day the rule was set; earlier days keep the to-do", DAY1, [
    record(define(e, "Water plants"), DAY1), summary(DAY1, DAY1, extras=["Water plants"]),
    record(schedule(e, every=2), DAY2, DAY2),
    summary(DAY1, DAY6, extras=["Water plants"]), summary(DAY2, DAY6, extras=["Water plants"]),
    summary(DAY3, DAY6, extras=[]), summary(DAY4, DAY6, extras=["Water plants"]), summary(DAY5, DAY6, extras=[]),
    summary(DAY6, DAY6, extras=["Water plants"]),
    {"op": "allExtras", "extras": [{"id": e, "title": "Water plants", "firstDay": D1, "completedOn": None,
                                    "archivedFrom": None, "schedule": "every 2"}]},
]))

e = uid()
cases.append(case("a schedule change applies from its day and archive ends a repeating extra", DAY1, [
    record(define(e, "Gym class"), DAY1), record(schedule(e, weekdays=[4]), DAY1),  # Thursdays
    summary(DAY1, DAY1, extras=["Gym class"]), record(schedule(e, weekdays=[4]), DAY2, DAY2, returns=None),
    record(schedule(e, weekdays=[6, 7]), DAY2, DAY2),  # weekends from Friday
    summary(DAY1, DAY4, extras=["Gym class"]), summary(DAY2, DAY4, extras=[]), summary(DAY3, DAY4, extras=["Gym class"]),
    summary(DAY4, DAY4, extras=["Gym class"]),
    record(archive(e), DAY4, DAY4), summary(DAY3, DAY4, extras=["Gym class"]), summary(DAY4, DAY4, extras=[]),
    {"op": "openExtras", "asOf": DAY4, "ids": []},
    record(schedule(e, every=1), DAY4, error="archivedExtra"),
    {"op": "allExtras", "extras": [{"id": e, "title": "Gym class", "firstDay": D1, "completedOn": None,
                                    "archivedFrom": D4, "schedule": "weekdays 6 7"}]},
]))

e = uid()
cases.append(case("a repeating extra switched back to a to-do is a fresh open to-do from that day", DAY1, [
    record(define(e, "Stretch"), DAY1), record(schedule(e, every=1), DAY1), record(tick(e), DAY1),
    record(schedule(e), DAY2, DAY2), record(schedule(e), DAY2, DAY2, returns=None),
    summary(DAY1, DAY4, extras=["Stretch ✓"]), summary(DAY2, DAY4, extras=["Stretch"]),
    summary(DAY3, DAY4, extras=["Stretch late"]),
    record(tick(e), DAY3, DAY4), summary(DAY3, DAY4, extras=["Stretch ✓ late"]), summary(DAY4, DAY4, extras=[]),
    {"op": "openExtras", "asOf": DAY4, "ids": []}, {"op": "openExtras", "asOf": DAY2, "ids": [e]},
    {"op": "allExtras", "extras": [{"id": e, "title": "Stretch", "firstDay": D1, "completedOn": D3,
                                    "archivedFrom": None, "schedule": "once"}]},
]))

e, other = uid(), uid()
first_rule, second_rule = uid(), uid()
batch = [activity(uid(), D2, DAY2, define(e, "Read"), "MAC"),
         # Both apply from the definition day; the later dated one wins although recorded first.
         activity(uid(), D2, plus(DAY2, -7200), schedule(e, weekdays=[5]), "PHONE"),
         activity(uid(), D1, plus(DAY2, -3600), schedule(e, weekdays=[4]), "PHONE"),
         # A tick from before the definition day is history only for a repeating extra.
         activity(uid(), D1, plus(DAY2, -100), tick(e), "PHONE"),
         activity(first_rule, D3, DAY3, schedule(e, every=3), "PHONE"),
         activity(second_rule, D3, DAY3, schedule(e, weekdays=[6]), "TABLET"),  # same time: device ID orders
         activity(uid(), D3, DAY3, define(other, "Journal"), "MAC")]
for name, events in [("in order", batch), ("reversed", list(reversed(batch)))]:
    cases.append(case(f"schedules from several devices apply from the definition day, then by event order ({name})", DAY1, [
        merge(events),
        summary(DAY1, DAY4, extras=[]), summary(DAY2, DAY4, extras=["Read"]),  # Friday, from the definition day
        summary(DAY3, DAY6, extras=["Read", "Journal"]), summary(DAY4, DAY6, extras=["Journal late"]),
        summary(DAY6, DAY6, extras=["Journal late"]),  # every 3 days would show Read here
        {"op": "allExtras", "extras": [
            {"id": e, "title": "Read", "firstDay": D2, "completedOn": None, "archivedFrom": None, "schedule": "weekdays 6"},
            {"id": other, "title": "Journal", "firstDay": D3, "completedOn": None, "archivedFrom": None, "schedule": "once"}]},
    ]))

e = uid()
cases.append(case("a to-do rule after a to-do changes nothing, so a done to-do stays done", DAY1, [
    merge([activity(uid(), D1, DAY1, define(e, "Stretch"), "MAC"), activity(uid(), D2, DAY2, schedule(e, every=1), "MAC"),
           activity(uid(), D3, DAY3, schedule(e), "PHONE"), activity(uid(), D3, plus(DAY3, 60), tick(e), "PHONE"),
           # The Mac, offline since day 2, also turns it back into a to-do a day later.
           activity(uid(), D4, DAY4, schedule(e), "MAC")]),
    summary(DAY2, DAY5, extras=["Stretch"]), summary(DAY3, DAY5, extras=["Stretch ✓"]),
    summary(DAY4, DAY5, extras=[]), summary(DAY5, DAY5, extras=[]),
    {"op": "allExtras", "extras": [{"id": e, "title": "Stretch", "firstDay": D1, "completedOn": D3,
                                    "archivedFrom": None, "schedule": "once"}]},
]))

ids = [uid() for _ in range(10)]
steps = [record(define(x, f"Extra {i}"), DAY1) for i, x in enumerate(ids)]
steps += [record(tick(ids[0]), DAY1), record(tick(ids[1]), DAY1), {"op": "openExtrasCount", "asOf": DAY1, "count": 8},
          record(schedule(ids[0], every=1), DAY1), {"op": "openExtrasCount", "asOf": DAY1, "count": 9},
          record(define(uid(), "Tenth"), DAY1), {"op": "openExtrasCount", "asOf": DAY1, "count": 10},
          record(define(uid(), "Eleventh"), DAY1, error="tooManyExtras"),
          record(schedule(ids[1], weekdays=[1]), DAY1, error="tooManyExtras"),
          record(schedule(ids[2], every=2), DAY1), {"op": "openExtrasCount", "asOf": DAY1, "count": 10},
          record(archive(ids[0]), DAY2, DAY2), {"op": "openExtrasCount", "asOf": DAY2, "count": 9},
          record(schedule(ids[1], weekdays=[1]), DAY2, DAY2), {"op": "openExtrasCount", "asOf": DAY2, "count": 10}]
cases.append(case("the cap counts open to-dos and active repeating extras", DAY1, steps))

e = uid()
cases.append(case("scheduling refuses unknown extras and invalid rules", DAY1, [
    record(schedule(uid(), every=1), DAY1, error="unknownExtra"),
    record(define(e, "Stretch"), DAY1),
    record(schedule(e, every=0), DAY1, error="invalidSchedule"), record(schedule(e, every=31), DAY1, error="invalidSchedule"),
    record(schedule(e, weekdays=[]), DAY1, error="invalidSchedule"), record(schedule(e, weekdays=[0]), DAY1, error="invalidSchedule"),
    record(schedule(e, weekdays=[8]), DAY1, error="invalidSchedule"), record(schedule(e, weekdays=[1, 1]), DAY1, error="invalidSchedule"),
    record(schedule(e, weekdays=[1], every=2), DAY1, error="invalidSchedule"),
    record(schedule(e), DAY1, returns=None),
    merge([activity(uid(), D1, DAY1, schedule(uid(), every=1), "MacB")], error="unknownExtra"),
    record(schedule(e, every=30), DAY1), record(schedule(e, weekdays=[7, 1, 2, 3, 4, 5, 6]), DAY1),
    {"op": "allExtras", "extras": [{"id": e, "title": "Stretch", "firstDay": D1, "completedOn": None,
                                    "archivedFrom": None, "schedule": "weekdays 1 2 3 4 5 6 7"}]},
]))

# Wire format. "sorted" is the exact text Swift's JSONEncoder writes with .sortedKeys.
E1 = "E1E1E1E1-0000-4000-8000-000000000001"
A1 = "AAAAAAAA-0000-4000-8000-000000000001"
P1 = "BBBBBBBB-0000-4000-8000-000000000001"
encoding = []
for action in [pour(450), UNDO, habit("walk"), habit("bibleReading", False), diet("clean"), diet("missed"),
               define(E1, "Stretch"), define(E1, "Lire 10 pages / jour é"), archive(E1), tick(E1), tick(E1, False),
               target("walk", "Yoga", 30, "minutes", "yoga"), target("bibleReading", "Audiobook", 20, "minutes", "headphones"),
               target("workout", "Gym"), target("diet", "No sugar"), target("walk", "Steps", 10000, "steps"),
               target("bibleReading", "😀" * 20, 500, "pages"), target("workout", "Run", icon="run"),
               target("walk", "Café / parc", 2, "kilometres"), target("walk", "Hike", 60, "miles"), target("bibleReading", "Psalms", 50, "chapters"),
               water(3000, 250), water(5000, 1000), water(1000, 50),
               schedule(E1, weekdays=[1, 2, 3, 4, 5]), schedule(E1, weekdays=[7]), schedule(E1, every=1), schedule(E1, every=30), schedule(E1)]:
    encoding.append({"kind": "action", "value": action})
encoding += [
    {"kind": "activity", "value": activity(A1, "2026-10-07T23:00:00Z", "2026-10-08T12:00:00Z", pour(450), "D3V1C3-A")},
    {"kind": "activity", "value": {"id": A1, "day": 781484400, "recordedAt": 781527600.25, "action": UNDO,
                                   "undonePourID": P1, "deviceID": "legacy-00000000000000000003"}},
    {"kind": "activity", "value": {"id": A1, "day": 781484400, "recordedAt": 781527600.125, "action": tick(E1)}},
    {"kind": "record", "value": {"id": A1, "owner_id": P1, "start_time": 1791414000, "time_zone": "Europe/Jersey"}},
    {"kind": "event", "value": {"id": A1, "activity": activity(A1, "2026-10-07T23:00:00Z", "2026-10-08T12:00:00Z",
                                                                habit("workout"), "D3V1C3-A"),
                                "owner_id": P1, "challenge_id": E1}},
]
for entry in encoding:
    entry["sorted"] = json.dumps(entry["value"], sort_keys=True, separators=(",", ":"), ensure_ascii=False).replace("/", "\\/")

# Accepted with a different spelling: decoding then encoding writes "sorted".
spellings = [
    {"kind": "activity", "value": {"id": A1.lower(), "day": 781484400, "recordedAt": 781527600, "action": pour(450), "deviceID": "x"},
     "sorted": json.dumps({"action": pour(450), "day": 781484400, "deviceID": "x", "id": A1, "recordedAt": 781527600},
                          sort_keys=True, separators=(",", ":"))},
    {"kind": "activity", "value": {"id": A1, "day": 781484400, "recordedAt": 781527600,
                                   "action": {"pour": {"_0": 450, "note": "ignored"}}, "deviceID": "x", "extra": 1},
     "sorted": json.dumps({"action": pour(450), "day": 781484400, "deviceID": "x", "id": A1, "recordedAt": 781527600},
                          sort_keys=True, separators=(",", ":"))},
    {"kind": "activity", "value": {"id": A1, "day": 781484400, "recordedAt": 781527600, "action": UNDO, "undonePourID": None},
     "sorted": json.dumps({"action": UNDO, "day": 781484400, "id": A1, "recordedAt": 781527600}, sort_keys=True, separators=(",", ":"))},
    {"kind": "record", "value": {"id": A1, "owner_id": P1, "start_time": 1791414000},
     "sorted": json.dumps({"id": A1, "owner_id": P1, "start_time": 1791414000, "time_zone": "Europe/Jersey"},
                          sort_keys=True, separators=(",", ":")).replace("/", "\\/")},
]
# Nil values are left out, null and unknown inner keys are ignored, weekday order is kept.
for value, written in [
    ({"setTarget": {"_0": "diet", "name": "Diet", "amount": None, "unit": None, "icon": None}}, target("diet", "Diet")),
    ({"setTarget": {"_0": "walk", "name": "Yoga", "colour": "red"}}, target("walk", "Yoga")),
    ({"scheduleExtra": {"id": E1.lower(), "weekdays": [5, 1], "every": None}}, schedule(E1, weekdays=[5, 1])),
    ({"setWater": {"goal": 3000, "pour": 250, "note": 1}}, water(3000, 250)),
]:
    spellings.append({"kind": "activity", "value": {"id": A1, "day": 781484400, "recordedAt": 781527600, "action": value, "deviceID": "x"},
                      "sorted": json.dumps({"action": written, "day": 781484400, "deviceID": "x", "id": A1, "recordedAt": 781527600},
                                           sort_keys=True, separators=(",", ":"), ensure_ascii=False)})

good = {"id": A1, "day": 781484400, "recordedAt": 781527600, "deviceID": "x"}
rejected = [{"kind": "activity", "value": {**good, "action": action}} for action in [
    {"pour": {"_0": 450}, "setDiet": {"_0": "clean"}}, {}, {"drinkCoffee": {}}, {"pour": {"_0": "450"}},
    {"pour": {"_0": 450.5}}, {"pour": {}}, {"setHabit": {"_0": "nap", "completed": True}}, {"setHabit": {"_0": "walk"}},
    {"setHabit": {"_0": "walk", "completed": "true"}}, {"setDiet": {"_0": "Clean"}}, {"defineExtra": {"id": E1}},
    {"setExtra": {"id": "1234", "completed": True}}, {"undoLatestPour": True}, "pour",
    # Targets and schedules outside the shared rules (the server refuses them too).
    target("water", "Water"), target("yoga", "Yoga"), target("walk", ""), target("walk", " Yoga"), target("walk", "Yoga "),
    target("walk", "Line\nbreak"), target("walk", "Tab\there"), target("walk", "x" * 21), target("walk", "👨‍👩‍👧"),
    target("walk", "e\u0301\u0302\u0303\u0304" * 20),
    {"setTarget": {"_0": "walk", "name": "Yoga", "amount": 30}}, {"setTarget": {"_0": "walk", "name": "Yoga", "unit": "minutes"}},
    target("walk", "Yoga", 30, "hours"), target("walk", "Yoga", 4, "minutes"), target("walk", "Yoga", 301, "minutes"),
    target("walk", "Yoga", 0, "pages"), target("walk", "Yoga", 501, "pages"), target("walk", "Yoga", 51, "chapters"),
    target("walk", "Yoga", 101, "kilometres"), target("walk", "Yoga", 61, "miles"), target("walk", "Yoga", 999, "steps"),
    target("walk", "Yoga", 50001, "steps"), {"setTarget": {"_0": "walk", "name": "Yoga", "amount": "30", "unit": "minutes"}},
    {"setTarget": {"_0": "walk", "name": "Yoga", "amount": 30.5, "unit": "minutes"}}, target("diet", "No sugar", 1, "pages"),
    target("walk", "Yoga", icon="Yoga"), target("walk", "Yoga", icon=""), target("walk", "Yoga", icon="a" * 17),
    target("walk", "Yoga", icon="run2"), {"setTarget": {"_0": "walk"}}, {"setTarget": {"name": "Yoga"}},
    {"setTarget": {"_0": "walk", "name": 7}}, {"setTarget": "walk"},
    water(999, 250), water(5001, 250), water(3000, 49), water(3000, 1001), water(1000, 1001), {"setWater": {"goal": 3000}},
    {"setWater": {"pour": 250}}, {"setWater": {"goal": "3000", "pour": 250}}, {"setWater": {"goal": 3000.5, "pour": 250}},
    {"scheduleExtra": {"id": "not-a-uuid", "every": 2}}, {"scheduleExtra": {"every": 2}}, schedule(E1, every=0),
    schedule(E1, every=31), schedule(E1, every=-1), schedule(E1, weekdays=[]), schedule(E1, weekdays=[0]),
    schedule(E1, weekdays=[8]), schedule(E1, weekdays=[1, 1]), schedule(E1, weekdays=[1, 2, 3, 4, 5, 6, 7, 1]),
    schedule(E1, weekdays=[1], every=2), {"scheduleExtra": {"id": E1, "weekdays": 1}}, {"scheduleExtra": {"id": E1, "every": "2"}},
    {"setTarget": {"_0": "walk", "name": "Yoga"}, "setWater": {"goal": 3000, "pour": 250}}]]
rejected += [{"kind": "activity", "value": value} for value in [
    {**good, "id": "1234", "action": pour(450)}, {**good, "day": "781484400", "action": pour(450)},
    {key: v for key, v in good.items() if key != "recordedAt"} | {"action": pour(450)},
    {**good, "deviceID": 7, "action": pour(450)}, {**good, "undonePourID": "nope", "action": UNDO}]]
rejected += [{"kind": "record", "value": {"id": A1, "owner_id": P1, "start_time": "1791414000"}},
             {"kind": "event", "value": {"id": A1, "owner_id": P1, "activity": {**good, "action": pour(450)}}}]

records = [  # Whether a server record describes a possible challenge.
    {"value": {"id": A1, "owner_id": P1, "start_time": 1791414000}, "timeZone": "Europe/Jersey", "valid": True},
    {"value": {"id": A1, "owner_id": P1, "start_time": 1791414000, "time_zone": "Australia/Sydney"}, "timeZone": "Australia/Sydney", "valid": False},
    {"value": {"id": A1, "owner_id": P1, "start_time": 1791414000, "time_zone": "Europe/London"}, "timeZone": "Europe/London", "valid": True},
    {"value": {"id": A1, "owner_id": P1, "start_time": 1791414001, "time_zone": "Europe/Jersey"}, "timeZone": "Europe/Jersey", "valid": False},
] + [{"value": {"id": A1, "owner_id": P1, "start_time": 1791414000, "time_zone": z}, "timeZone": z, "valid": False}
     for z in ["Bogus/Zone", "", "UTC"]]

zones = [{"identifier": z, "canonical": True} for z in
         ["Europe/Jersey", "Europe/London", "America/New_York", "Australia/Sydney", "GMT", "Asia/Kolkata", "America/Argentina/Buenos_Aires"]]
zones += [{"identifier": z, "canonical": False} for z in ["UTC", "", "Mars/Olympus_Mons", "europe/london", "Bogus/Zone"]]

titles = [{"raw": raw, "title": title} for raw, title in [
    ("  Walk the dog \n", "Walk the dog"), ("x" * 40, "x" * 40), ("x" * 41, None), ("", None), ("   ", None),
    ("Two\nlines", None), ("Tab\there", None), ("é" * 40, "é" * 40), ("é" * 40, "é" * 40),
    ("👍🏽" * 40, "👍🏽" * 40), ("👍🏽" * 41, None), ("👨‍👩‍👧", None), (" Padded ", "Padded"),
    ("Zero​width", None), ("Line separated", None), ("Café crème", "Café crème")]]

# A slot's stored name: like an extra's title but at most 20 characters and 80 Unicode scalars.
target_names = [{"raw": raw, "name": name} for raw, name in [
    ("  Yoga \n", "Yoga"), ("x" * 20, "x" * 20), ("x" * 21, None), ("", None), ("   ", None), ("Two\nlines", None),
    ("Tab\there", None), ("é" * 20, "é" * 20), ("👍🏽" * 20, "👍🏽" * 20), ("👍🏽" * 21, None), ("👨‍👩‍👧", None),
    ("e\u0301\u0302\u0303" * 20, "e\u0301\u0302\u0303" * 20), ("e\u0301\u0302\u0303\u0304" * 20, None),
    ("Zero\u200bwidth", None), ("No sugar", "No sugar"), ("Café crème", "Café crème")]]

icons = [{"id": i, "valid": v} for i, v in [("yoga", True), ("a", True), ("a" * 16, True), ("a" * 17, False), ("", False),
                                              ("Yoga", False), ("run2", False), ("dumb-bell", False), ("é", False)]]

clock = [{"recordedAt": "2026-10-08T12:00:00Z", "receivedAt": received, "warning": warning} for received, warning in [
    ("2026-10-08T11:54:59Z", True), ("2026-10-08T11:55:00Z", False), ("2026-10-08T12:00:00Z", False),
    ("2026-10-08T13:00:00Z", False), ("2026-10-09T12:00:00Z", False),
    ("2026-10-08T11:54:59.123456+00:00", True), ("2026-10-08T12:54:59.5+01:00", True), ("2026-10-08T12:00:00.123+00:00", False)]]

out = {"about": "Generated by test-vectors/generate.py; run by the Swift and Android tests. Instants are ISO 8601 "
                "or, inside wire activities, seconds since 2001-01-01T00:00:00Z.",
       "cases": cases, "encoding": encoding, "spellings": spellings, "rejected": rejected,
       "records": records, "zones": zones, "titles": titles, "targetNames": target_names, "icons": icons,
       "clockWarnings": clock}
path = Path(__file__).with_name("challenge-rules.json")
path.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
print(f"{path.name}: {len(cases)} cases, {len(encoding)} encodings, {len(rejected)} rejections")

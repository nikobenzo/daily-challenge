package app.dailychallenge.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.ZoneId
import java.util.UUID

/**
 * Ports of ChallengeTargetsTests.swift: custom daily targets in the store, its file and the
 * reminder planner. The day rules themselves are in the shared parity vectors.
 */
class TargetsTest {
    @get:Rule val folder = TemporaryFolder()

    private val jersey: ZoneId = ZoneId.of("Europe/Jersey")
    private val day1 = ChallengeTime.parse("2026-10-08T12:00:00Z")
    private val day2 = day1 + 86_400
    private val day3 = day2 + 86_400

    private val custom = Targets.STANDARD.copy(
        water = WaterTarget(3_000, 250),
        walk = Target("Yoga", 30, TargetUnit.MINUTES, "yoga"),
        bibleReading = Target("Audiobook", 20, TargetUnit.MINUTES, "headphones"),
    )

    private fun refused(expected: ChallengeError, block: () -> Unit) {
        try {
            block()
            fail("Expected $expected")
        } catch (error: ChallengeException) {
            assertEquals(expected, error.error)
        }
    }

    @Test
    fun standardTargetsAreTheOriginalFiveAndWriteNothing() {
        assertEquals(WaterTarget(4_000, 450), Targets.STANDARD.water)
        assertEquals(Target("Workout", 45, TargetUnit.MINUTES), Targets.STANDARD.workout)
        assertEquals(Target("Bible", 10, TargetUnit.PAGES), Targets.STANDARD.bibleReading)
        assertTrue(Targets.STANDARD.changes().isEmpty())
        assertTrue(TargetSlot.entries.all { Targets.STANDARD[it].isValid(it) } && Targets.STANDARD.water.isValid)
        assertEquals(listOf(Action.SetWater(3_000, 250), Action.SetTarget(TargetSlot.WALK, "Yoga", 30, TargetUnit.MINUTES, "yoga"),
            Action.SetTarget(TargetSlot.BIBLE_READING, "Audiobook", 20, TargetUnit.MINUTES, "headphones")), custom.changes())
        assertEquals(Action.ScheduleExtra(UUID(0, 1), weekdays = listOf(1L, 3L, 5L)), ExtraSchedule.Weekdays(setOf(5, 1, 3)).action(UUID(0, 1)))
    }

    @Test
    fun setupWithCustomTargetsCommitsThemWithTheSettingsOnTheStartDay() {
        val owner = UUID.randomUUID()
        val directory = folder.newFolder()
        val store = ChallengeStore(owner, directory)
        // A start date in the past: the targets apply from that day, recorded now.
        store.start(day1, jersey, custom, day3)
        val challenge = store.challenge!!
        assertEquals(3, store.pending.size)
        assertEquals(4, store.pendingCount) // and the settings header
        assertTrue(store.pending.all { it.activity.day == challenge.startDate && it.activity.recordedAt == day3 })
        assertEquals(custom.changes(), store.pending.map { it.activity.action })
        assertEquals(custom, challenge.targets(day1))
        assertEquals(custom, challenge.targets(day3))
        // One atomic file, the snapshot shape the Apple apps write: reopening finds the same.
        val reopened = ChallengeStore(owner, directory)
        assertEquals(store.pending.map { it.id }, reopened.pending.map { it.id })
        assertEquals(custom, reopened.challenge!!.targets(day2))

        val plain = ChallengeStore(UUID.randomUUID(), directory)
        plain.start(day1, jersey, Targets.STANDARD, day1)
        assertTrue(plain.pending.isEmpty())
        assertEquals(1, plain.pendingCount)
    }

    @Test
    fun setupRefusesInvalidTargetsWithoutWritingAnything() {
        val directory = folder.newFolder()
        val store = ChallengeStore(UUID.randomUUID(), directory)
        refused(ChallengeError.INVALID_TARGET) { store.start(day1, jersey, custom.copy(water = WaterTarget(999, 250)), day1) }
        refused(ChallengeError.INVALID_TARGET) {
            store.start(day1, jersey, custom.copy(diet = Target("No sugar", 1, TargetUnit.PAGES)), day1)
        }
        // A start after `at` cannot hold events dated on it.
        refused(ChallengeError.DATE_OUTSIDE_CHALLENGE) { store.start(day2, jersey, custom, day1) }
        assertNull(store.challenge)
        assertFalse(store.file.exists())
    }

    @Test
    fun recurringExtrasSurviveTheStoreFile() {
        val owner = UUID.randomUUID()
        val directory = folder.newFolder()
        val store = ChallengeStore(owner, directory)
        store.start(day1, jersey, custom, day1)
        val extra = UUID.randomUUID()
        store.record(Action.DefineExtra(extra, "Stretch"), day1, day1 + 1)
        store.record(Action.ScheduleExtra(extra, every = 1), day1, day1 + 2)
        store.record(Action.SetExtra(extra, true), day2, day2)
        val reopened = ChallengeStore(owner, directory).challenge!!
        assertEquals(store.challenge!!.allExtras, reopened.allExtras)
        assertEquals(ExtraSchedule.Every(1), reopened.allExtras.single().schedule)
        assertEquals(listOf(extra), reopened.extras(day3).map { it.id })
    }

    @Test
    fun remindersStopOnceThatDaysOwnGoalIsMet() {
        val now = day1 // 13:00 Jersey
        val settings = WaterReminderSettings(enabled = true, intervalMinutes = 60, startMinute = 9 * 60, endMinute = 21 * 60)
        val planner = WaterReminderPlanner(jersey) { now }
        val calendar = ChallengeCalendar(jersey)
        val today = calendar.startOfDay(now)
        val tomorrow = calendar.addDays(today, 1)
        val horizon = calendar.addDays(today, 2)
        // 3,150 ml meets a 3,000 ml goal, so only tomorrow (a 4,000 ml day) is planned.
        val lowered = planner.upcoming(settings, horizon, { if (it == today) 3_000L else 4_000L }) { 3_150L }
        assertTrue(lowered.isNotEmpty() && lowered.all { it >= tomorrow })
        // Raised above the total, today is planned again.
        assertTrue(planner.upcoming(settings, horizon, { 3_500L }) { 3_150L }.any { it < tomorrow })
        // Without a goal the standard 4,000 ml applies, as before.
        assertTrue(planner.upcoming(settings, horizon) { 4_000L }.isEmpty())

        val scheduler = object : ReminderScheduler {
            override fun permission() = NotificationPermission.ALLOWED
            override fun replace(dates: List<Double>, zone: ZoneId) = Unit
            override fun cancel() = Unit
        }
        val controller = WaterReminderController(MemoryKeyValueStore(), scheduler, DeviceWording.android) { now }
        controller.update(settings)
        controller.refresh(3_150, 0, jersey, waterGoal = 3_000)
        assertEquals("Permission allowed · Today's water goal met.", controller.status)
        assertTrue(controller.scheduledDates.all { it >= tomorrow })
        controller.refresh(3_150, 0, jersey)
        assertTrue(controller.status.startsWith("Permission allowed · Reminders enabled"))
        assertTrue(controller.scheduledDates.any { it < tomorrow })
    }
}

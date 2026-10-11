package app.dailychallenge.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

/** Ports of WaterReminderPlannerTests.swift and QueuedReminderTests.swift. */
class WaterReminderTest {
    private val jersey = ZoneId.of("Europe/Jersey")
    private fun at(iso: String) = ChallengeTime.parse(iso)

    private fun plan(date: String, settings: WaterReminderSettings = WaterReminderSettings(enabled = true), water: Long? = 0): List<Double> {
        val now = at(date)
        val end = ChallengeCalendar(jersey).interval(now).second - 1
        return WaterReminderPlanner(jersey) { now }.upcoming(settings, end) { water }
    }

    @Test
    fun defaultSlotsAreAnchoredToTheZoneAndIncludeNineAndTwentyOne() {
        val dates = plan("2026-10-08T07:59:00Z")
        assertEquals(9, dates.size)
        assertEquals(at("2026-10-08T08:00:00Z"), dates.first(), 0.0)
        assertEquals(at("2026-10-08T20:00:00Z"), dates.last(), 0.0)
        assertTrue(dates.zipWithNext().all { (a, b) -> b - a == 90.0 * 60 })
        assertEquals(listOf(at("2026-10-08T20:00:00Z")), plan("2026-10-08T19:59:59Z"))
        assertTrue(plan("2026-10-08T20:00:00Z").isEmpty())
    }

    @Test
    fun goalsUndoAndAMissingChallengePlanOnlyFutureSlots() {
        assertTrue(plan("2026-10-08T10:15:00Z", water = 4_000).isEmpty())
        assertTrue(plan("2026-10-08T10:15:00Z", water = null).isEmpty())
        assertEquals(at("2026-10-08T11:00:00Z"), plan("2026-10-08T10:15:00Z", water = 3_999).first(), 0.0)
        assertTrue(plan("2026-10-08T10:15:00Z", settings = WaterReminderSettings()).isEmpty())
        val custom = WaterReminderSettings(enabled = true, intervalMinutes = 40, startMinute = 600, endMinute = 690)
        assertEquals(listOf("2026-10-08T09:00:00Z", "2026-10-08T09:40:00Z", "2026-10-08T10:20:00Z").map(::at),
            plan("2026-10-08T08:00:00Z", settings = custom))
        assertTrue(plan("2026-10-08T08:00:00Z", settings = WaterReminderSettings(true, 0)).isEmpty())
        assertTrue(plan("2026-10-08T08:00:00Z", settings = WaterReminderSettings(true, 90, 1300, 400)).isEmpty())
    }

    @Test
    fun daylightSavingSkipsMissingTimesAndRepeatedTimesOccurOnce() {
        assertEquals(at("2026-03-29T08:00:00Z"), plan("2026-03-29T00:00:00Z").first(), 0.0)
        assertEquals(at("2026-10-25T21:00:00Z"), plan("2026-10-25T00:00:00Z").last(), 0.0)
        val settings = WaterReminderSettings(enabled = true, intervalMinutes = 30, startMinute = 60, endMinute = 150)
        assertEquals(listOf("2026-03-29T01:00:00Z", "2026-03-29T01:30:00Z").map(::at), plan("2026-03-29T00:00:00Z", settings))
        assertEquals(listOf("2026-10-25T00:00:00Z", "2026-10-25T00:30:00Z", "2026-10-25T02:00:00Z", "2026-10-25T02:30:00Z").map(::at),
            plan("2026-10-24T23:00:00Z", settings))
    }

    private class Scheduler : ReminderScheduler {
        var pending: List<Double> = emptyList()
        var allowed = NotificationPermission.ALLOWED
        override fun permission() = allowed
        override fun replace(dates: List<Double>, zone: ZoneId) { pending = dates }
        override fun cancel() { pending = emptyList() }
    }

    private fun jerseyTime(day: Int, hour: Int) =
        ChallengeTime.fromInstant(java.time.ZonedDateTime.of(2026, 10, day, hour, 0, 0, 0, jersey).toInstant())

    @Test
    fun everyRemainingSlotOfTodayAndTomorrowIsQueuedAndTheGoalDropsToday() {
        val scheduler = Scheduler()
        val defaults = MemoryKeyValueStore()
        val controller = WaterReminderController(defaults, scheduler, DeviceWording.android) { jerseyTime(8, 11) }
        controller.refresh(450, 0, jersey)
        controller.update(WaterReminderSettings(enabled = true))
        assertEquals(16, scheduler.pending.size)
        assertEquals(jerseyTime(8, 12), scheduler.pending.first(), 0.0)
        assertEquals(jerseyTime(9, 21), scheduler.pending.last(), 0.0)
        assertEquals("Permission allowed · Reminders enabled on this phone. Delivery depends on Android and Do Not Disturb.", controller.status)
        controller.refresh(4_050, 0, jersey)
        assertEquals(9, scheduler.pending.size)
        assertEquals(jerseyTime(9, 9), scheduler.pending.first(), 0.0)
        // The setting survives a relaunch; turning it off cancels everything.
        assertTrue(WaterReminderController(defaults, scheduler, DeviceWording.android).settings.enabled)
        controller.update(WaterReminderSettings(enabled = false))
        assertTrue(scheduler.pending.isEmpty())
        assertEquals("Permission allowed · Reminders off on this phone.", controller.status)
        scheduler.allowed = NotificationPermission.DENIED
        controller.update(WaterReminderSettings(enabled = true))
        assertTrue(scheduler.pending.isEmpty())
        assertTrue(controller.status.startsWith("Notifications are off for this app."))
    }

    @Test
    fun syncWordingNamesThePhone() {
        assertEquals("Saved on this phone, 2 changes waiting", SyncState.SavedLocally(2).plainText(DeviceWording.android) { "" })
        assertEquals("This phone's clock looks ahead of the server; check Settings > System > Date & time if this keeps happening",
            SyncState.Synced(0.0, true).clockWarningText(DeviceWording.android))
    }
}

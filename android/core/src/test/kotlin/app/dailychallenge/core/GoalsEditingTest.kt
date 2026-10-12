package app.dailychallenge.core

import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/**
 * What the editors call on the tracker: pours of the day's glass, daily goals changed from today,
 * repeating extras added and rescheduled in one commit, and a server without the custom goals
 * update refusing the upload without losing anything.
 */
class GoalsEditingTest {
    @get:Rule val folder = TemporaryFolder()
    private val jersey = ZoneId.of("Europe/Jersey")
    private val owner = UUID.randomUUID()
    private val server = FixtureServer()
    private val calendar = ChallengeCalendar(jersey)
    private val today: LocalDate get() = calendar.localDate(server.now)

    private fun TestScope.model(): Tracker {
        val model = Tracker(folder.root, this, clock = { server.now }, deviceZone = { jersey })
        model.configureSync(server)
        model.activate(owner)
        return model
    }

    private val custom = Targets.STANDARD.copy(water = WaterTarget(3_000, 330), walk = Target("Yoga", 30, TargetUnit.MINUTES, "yoga"))

    @Test
    fun plusPoursTheGlassInForceOnTheSelectedDay() = runTest {
        val model = model()
        model.sync()
        model.startChallenge(today.minusDays(2), jersey, Targets.STANDARD.copy(water = WaterTarget(2_000, 250)))
        assertEquals(null, model.setGoals(custom))
        model.addWater()
        assertEquals(330L, model.summary!!.waterMillilitres)
        // A correction on an earlier day pours that day's glass.
        model.selectHistoryDay(calendar.addDays(server.now, -1)); model.enableCorrections()
        model.addWater()
        assertEquals(250L, model.summary!!.waterMillilitres)
        model.addWater(1_000)
        assertEquals(1_250L, model.summary!!.waterMillilitres)
    }

    @Test
    fun goalsChangeFromTodayAndEarlierDaysKeepTheirs() = runTest {
        val model = model()
        model.sync()
        model.startChallenge(today.minusDays(1), jersey)
        val before = model.store!!.pendingCount
        assertNull(model.setGoals(custom))
        assertEquals(custom, model.todayTargets)
        assertEquals(Targets.STANDARD, model.challenge!!.targets(calendar.addDays(server.now, -1)))
        // Only the changed values, recorded today.
        val written = model.challenge!!.allActivities.filter { it.action is Action.SetWater || it.action is Action.SetTarget }
        assertEquals(listOf(Action.SetWater(3_000, 330), Action.SetTarget(TargetSlot.WALK, "Yoga", 30, TargetUnit.MINUTES, "yoga")),
            written.map { it.action })
        assertTrue(written.all { it.day == calendar.startOfDay(server.now) })
        assertEquals(before + 2, model.store!!.pendingCount)
        // The same goals again write nothing; an invalid one refuses all of them.
        assertNull(model.setGoals(custom))
        assertEquals(before + 2, model.store!!.pendingCount)
        val refused = model.setGoals(custom.copy(workout = Target("Gym", 400, TargetUnit.MINUTES), water = WaterTarget(2_500, 330)))
        assertEquals(ChallengeError.INVALID_TARGET.message, refused)
        assertEquals(custom, model.todayTargets)
        assertEquals(before + 2, model.store!!.pendingCount)
        // Lowering today's goal below today's total completes water at once.
        repeat(8) { model.addWater() }
        assertNull(model.setGoals(custom.copy(water = WaterTarget(2_500, 330))))
        assertTrue(model.summary!!.waterComplete)
    }

    @Test
    fun repeatingExtrasAreAddedAndRescheduledInOneCommit() = runTest {
        val model = model()
        model.sync()
        model.startChallenge(today, jersey)
        val before = model.store!!.pendingCount
        assertNull(model.addExtra("Stretch", ExtraSchedule.Every(1)))
        val stretch = model.activeExtras.single()
        assertEquals(ExtraSchedule.Every(1), stretch.schedule)
        assertEquals(before + 2, model.store!!.pendingCount)
        assertNull(model.scheduleExtra(stretch.id, ExtraSchedule.Weekdays(setOf(1, 2, 3, 4, 5, 6, 7))))
        assertEquals(ExtraSchedule.Weekdays(setOf(1, 2, 3, 4, 5, 6, 7)), model.activeExtras.single().schedule)
        // The rule already in force records nothing; an invalid one is refused with nothing written.
        assertNull(model.scheduleExtra(stretch.id, ExtraSchedule.Weekdays(setOf(1, 2, 3, 4, 5, 6, 7))))
        assertEquals(ChallengeError.INVALID_SCHEDULE.message, model.scheduleExtra(stretch.id, ExtraSchedule.Every(31)))
        assertEquals(ChallengeError.INVALID_SCHEDULE.message, model.addExtra("Read", ExtraSchedule.Weekdays(emptySet())))
        assertEquals(1, model.activeExtras.size)
        assertEquals(before + 3, model.store!!.pendingCount)
        // Back to a to-do from today.
        assertNull(model.scheduleExtra(stretch.id, ExtraSchedule.Once))
        assertEquals(ExtraSchedule.Once, model.activeExtras.single().schedule)
        // Repeating extras count toward the cap of 10.
        repeat(9) { assertNull(model.addExtra("Item $it", ExtraSchedule.Weekdays(setOf(6, 7)))) }
        assertEquals(ChallengeError.TOO_MANY_EXTRAS.message, model.addExtra("One more", ExtraSchedule.Every(2)))
        assertEquals(10, model.activeExtras.size)
    }

    @Test
    fun aServerWithoutTheCustomGoalsUpdateKeepsEverythingPending() = runTest {
        val model = model()
        model.sync()
        model.startChallenge(today, jersey)
        model.sync()
        assertEquals(0, model.store!!.pendingCount)
        val unmigrated = object : ChallengeTransport by server {
            override suspend fun upload(events: List<ChallengeEvent>, ownerID: UUID) {
                // What SupabaseChallengeTransport reports for 23514 on the old action-kind check.
                if (events.any { it.activity.action is Action.SetWater || it.activity.action is Action.SetTarget }) {
                    throw ChallengeSyncException(ChallengeSyncError.SERVER_NEEDS_CUSTOM_GOALS_UPDATE)
                }
                server.upload(events, ownerID)
            }
        }
        model.configureSync(unmigrated)
        model.addWater()
        assertNull(model.setGoals(custom))
        model.sync(force = true)
        assertEquals(ChallengeSyncError.SERVER_NEEDS_CUSTOM_GOALS_UPDATE.message, model.syncError)
        assertEquals(SyncState.Unavailable(3, ChallengeSyncError.SERVER_NEEDS_CUSTOM_GOALS_UPDATE.message), model.syncState)
        assertEquals(custom, model.todayTargets)
        assertEquals(450L, model.summary!!.waterMillilitres)
        // Once the owner applies the migration, the same queue uploads and nothing was lost.
        model.configureSync(server)
        model.sync(force = true)
        assertNull(model.syncError)
        assertEquals(0, model.store!!.pendingCount)
        assertEquals(custom, model.todayTargets)
    }
}

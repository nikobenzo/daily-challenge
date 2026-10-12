package app.dailychallenge.core

import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CountDownLatch
import kotlin.concurrent.thread

/**
 * Widget taps against the real store and lock (the iPhone's WidgetActionRecorder tests): each tap
 * is an existing action decided from the stored state at the tap's own time, recorded into the
 * pending queue, and refused once the published account changes.
 */
class WidgetActionsTest {
    @get:Rule val folder = TemporaryFolder()
    private val jersey = ZoneId.of("Europe/Jersey")
    private val owner = UUID.randomUUID()
    /** Thursday 8 October 2026, 13:00 in Jersey. */
    private var now = ChallengeTime.parse("2026-10-08T12:00:00Z")
    private lateinit var directory: File

    private fun setUp(zone: ZoneId = jersey, startDaysAgo: Long = 3): Pair<ChallengeStore, WidgetBinding> {
        directory = folder.newFolder()
        val account = WidgetAccountStore(directory).publish(owner)!!
        val store = ChallengeStore(owner, directory)
        store.start(ChallengeCalendar(zone).addDays(now, -startDaysAgo), zone)
        return store to WidgetBinding(account.generation, store.record!!.id)
    }

    private fun actions() = WidgetActions(directory) { now }
    private fun reopened() = ChallengeStore(owner, directory)
    private fun today() = reopened().challenge!!.summary(now, now)

    @Test
    fun pourRecordsFourHundredFiftyMillilitresIntoThePendingQueue() {
        val (_, binding) = setUp()
        val outcome = actions().perform(WidgetTap.Pour, binding)
        assertTrue(outcome is WidgetOutcome.Recorded)
        val store = reopened()
        assertEquals(450L, store.challenge!!.summary(now, now).waterMillilitres)
        assertEquals(listOf((outcome as WidgetOutcome.Recorded).eventID), store.pending.map { it.id })
        // Two taps are two pours, never merged into one.
        actions().perform(WidgetTap.Pour, binding)
        assertEquals(900L, today().waterMillilitres)
        assertEquals(2, reopened().pending.size)
    }

    @Test
    fun pourPastTheGoalStillRecordsTheActualAmount() {
        val (store, binding) = setUp()
        store.record(Action.Pour(4_000), now, now)
        actions().perform(WidgetTap.Pour, binding)
        assertEquals(4_450L, today().waterMillilitres)
    }

    @Test
    fun undoWithoutAPourTodayRecordsNothing() {
        val (store, binding) = setUp()
        // Yesterday's pour is never touched from today's widget.
        val yesterday = ChallengeCalendar(jersey).addDays(now, -1) + 3_600
        store.record(Action.Pour(450), yesterday, yesterday)
        val before = store.file.readText()
        assertEquals(WidgetOutcome.Unchanged, actions().perform(WidgetTap.UndoPour, binding))
        assertEquals(before, store.file.readText())
        assertEquals(450L, reopened().challenge!!.summary(yesterday, now).waterMillilitres)
    }

    @Test
    fun undoRemovesTodaysLatestPourWhateverItsAmountOrDevice() {
        val (store, binding) = setUp()
        store.record(Action.Pour(450), now - 60, now - 60)
        store.record(Action.Pour(250), now - 30, now - 30)
        val outcome = actions().perform(WidgetTap.UndoPour, binding) as WidgetOutcome.Recorded
        val summary = today()
        assertEquals(450L, summary.waterMillilitres)
        val undo = reopened().challenge!!.allActivities.single { it.id == outcome.eventID }
        assertEquals(Action.UndoLatestPour, undo.action)
        assertEquals(store.challenge!!.allActivities.first { (it.action as? Action.Pour)?.millilitres == 250L }.id, undo.undonePourID)
        // A pour synced from another device is today's latest too.
        val remote = Activity(UUID.randomUUID(), ChallengeCalendar(jersey).startOfDay(now), now - 10, Action.Pour(300), null, "OTHER-DEVICE")
        reopened().merge(store.record!!, confirmed(listOf(ChallengeEvent(owner, store.record!!.id, remote))))
        actions().perform(WidgetTap.UndoPour, binding)
        assertEquals(450L, today().waterMillilitres)
    }

    @Test
    fun habitTapReversesTheStoredStateNotTheDrawnOne() {
        val (_, binding) = setUp()
        actions().perform(WidgetTap.ToggleHabit(Habit.WORKOUT), binding)
        assertTrue(Habit.WORKOUT in today().completedHabits)
        // The app ticked walk meanwhile; a widget drawn before that still unticks only what is stored.
        ChallengeStore(owner, directory).record(Action.SetHabit(Habit.WALK, true), now, now)
        actions().perform(WidgetTap.ToggleHabit(Habit.WALK), binding)
        actions().perform(WidgetTap.ToggleHabit(Habit.WORKOUT), binding)
        assertEquals(emptySet<Habit>(), today().completedHabits)
        actions().perform(WidgetTap.ToggleHabit(Habit.BIBLE_READING), binding)
        assertEquals(setOf(Habit.BIBLE_READING), today().completedHabits)
    }

    @Test
    fun dietTogglesPendingAndCleanAndLeavesAMissedDayToTheApp() {
        val (_, binding) = setUp()
        actions().perform(WidgetTap.ToggleDiet, binding)
        assertEquals(DietState.CLEAN, today().diet)
        actions().perform(WidgetTap.ToggleDiet, binding)
        assertEquals(DietState.PENDING, today().diet)
        ChallengeStore(owner, directory).record(Action.SetDiet(DietState.MISSED), now, now)
        val before = reopened().challenge!!.allActivities.size
        assertEquals(WidgetOutcome.OpenApp, actions().perform(WidgetTap.ToggleDiet, binding))
        assertEquals(DietState.MISSED, today().diet)
        assertEquals(before, reopened().challenge!!.allActivities.size)
    }

    @Test
    fun extrasTickWhileShownTodayAndRefuseArchivedUnknownOrFinishedOnes() {
        val (store, binding) = setUp()
        val stretch = UUID.randomUUID()
        val archived = UUID.randomUUID()
        val finished = UUID.randomUUID()
        val earlier = ChallengeCalendar(jersey).addDays(now, -2) + 3_600
        store.record(Action.DefineExtra(stretch, "Stretch"), earlier, earlier)
        store.record(Action.DefineExtra(archived, "Old habit"), earlier, earlier)
        store.record(Action.DefineExtra(finished, "Call family"), earlier, earlier)
        store.record(Action.SetExtra(finished, true), earlier, earlier)
        store.record(Action.ArchiveExtra(archived), now, now)
        actions().perform(WidgetTap.ToggleExtra(stretch), binding)
        assertEquals(setOf(stretch), today().completedExtras)
        actions().perform(WidgetTap.ToggleExtra(stretch), binding)
        assertEquals(emptySet<UUID>(), today().completedExtras)
        val before = reopened().challenge!!.allActivities.size
        assertEquals(WidgetOutcome.Refused, actions().perform(WidgetTap.ToggleExtra(archived), binding))
        assertEquals(WidgetOutcome.Refused, actions().perform(WidgetTap.ToggleExtra(finished), binding))
        assertEquals(WidgetOutcome.Refused, actions().perform(WidgetTap.ToggleExtra(UUID.randomUUID()), binding))
        assertEquals(before, reopened().challenge!!.allActivities.size)
    }

    @Test
    fun tapsAreRefusedAfterSignOutAccountSwitchOrDeletion() {
        val (store, binding) = setUp()
        val accounts = WidgetAccountStore(directory)
        // Relaunching the app republishes the same account and keeps its generation.
        assertEquals(binding.generation, accounts.publish(owner)!!.generation)
        accounts.publish(null)
        assertNull(accounts.read())
        assertEquals(WidgetOutcome.Refused, actions().perform(WidgetTap.Pour, binding))
        // Another account, then the first one again: either way a new generation.
        accounts.publish(UUID.randomUUID())
        assertEquals(WidgetOutcome.Refused, actions().perform(WidgetTap.Pour, binding))
        val again = accounts.publish(owner)!!
        assertNotEquals(binding.generation, again.generation)
        assertEquals(WidgetOutcome.Refused, actions().perform(WidgetTap.Pour, binding))
        assertEquals(0L, today().waterMillilitres)
        // Deletion unpublishes, then removes the history.
        accounts.publish(null)
        ChallengeStore.removeAccountFiles(owner, directory)
        assertEquals(WidgetOutcome.Refused, actions().perform(WidgetTap.Pour, WidgetBinding(again.generation, store.record!!.id)))
        assertFalse(store.file.exists())
        assertEquals(WidgetState.SignedOut, WidgetState.load(directory, now))
    }

    @Test
    fun aBindingForAnotherChallengeIsRefused() {
        val (_, binding) = setUp()
        assertEquals(WidgetOutcome.Refused, actions().perform(WidgetTap.Pour, binding.copy(challengeID = UUID.randomUUID())))
        assertEquals(0, reopened().pending.size)
    }

    @Test
    fun theDayComesFromTheTapTimeInTheChallengesZone() {
        // A New York challenge on a phone anywhere: 23:59 there is still Thursday, 00:01 is Friday.
        val newYork = ZoneId.of("America/New_York")
        now = ChallengeTime.parse("2026-10-09T03:59:00Z")
        val (_, binding) = setUp(newYork)
        val drawn = WidgetState.load(directory, now) as WidgetState.Ready
        assertTrue(drawn.dateLabel.startsWith("8 Oct"))
        now = ChallengeTime.parse("2026-10-09T04:01:00Z")
        val outcome = actions().perform(WidgetTap.Pour, binding) as WidgetOutcome.Recorded
        val event = reopened().challenge!!.allActivities.single { it.id == outcome.eventID }
        assertEquals(ChallengeTime.parse("2026-10-09T04:00:00Z"), event.day, 0.0)
        assertEquals(0L, reopened().challenge!!.summary(ChallengeTime.parse("2026-10-09T03:00:00Z"), now).waterMillilitres)
    }

    @Test
    fun aDayBeforeTheStartIsRefused() {
        val (_, binding) = setUp(startDaysAgo = 0)
        now -= 86_400
        assertEquals(WidgetOutcome.Refused, actions().perform(WidgetTap.Pour, binding))
    }

    @Test
    fun forgedParametersDoNotParse() {
        assertNull(WidgetTap.parse("habit", "sleep"))
        assertNull(WidgetTap.parse("extra", "not-an-id"))
        assertNull(WidgetTap.parse("delete", ""))
        assertEquals(WidgetTap.ToggleHabit(Habit.BIBLE_READING), WidgetTap.parse("habit", "bibleReading"))
        val id = UUID.randomUUID()
        val tap = WidgetTap.ToggleExtra(id)
        assertEquals(tap, WidgetTap.parse(tap.kind, tap.target))
    }

    private fun TestScope.tracker(server: FixtureServer? = null): Tracker {
        val model = Tracker(directory, this, clock = { now }, deviceZone = { jersey })
        server?.let { model.configureSync(it) }
        model.activate(owner)
        return model
    }

    @Test
    fun anAppEditAfterAWidgetTapKeepsBoth() = runTest {
        val (_, binding) = setUp()
        val model = tracker()
        var commits = 0
        model.onCommitted = { commits++ }
        // The app holds the history it loaded before the tap.
        actions().perform(WidgetTap.Pour, binding)
        model.addWater()
        model.toggle(Habit.WALK)
        assertEquals(900L, today().waterMillilitres)
        assertEquals(900L, model.summary!!.waterMillilitres)
        assertEquals(setOf(Habit.WALK), today().completedHabits)
        assertEquals(3, reopened().pending.size)
        assertEquals(2, commits)
    }

    @Test
    fun aSyncMergeKeepsATapMadeWhileItsRequestWasInFlight() = runTest {
        val (store, binding) = setUp()
        val server = FixtureServer(now)
        server.headers[owner] = store.record!!
        val model = tracker(server)
        model.addWater()
        var tapped: WidgetOutcome? = null
        server.eventsHook = { tapped = actions().perform(WidgetTap.Pour, binding) }
        model.sync(force = true)
        val widgetPour = (tapped as WidgetOutcome.Recorded).eventID
        assertEquals(900L, today().waterMillilitres)
        // Uploaded and fetched: acknowledged. Recorded after the fetch: still waiting.
        assertEquals(listOf(widgetPour), reopened().pending.map { it.id })
        model.sync(force = true)
        assertEquals(0, reopened().pending.size)
        assertEquals(2, server.events[owner]!!.size)
        assertEquals(900L, model.summary!!.waterMillilitres)
    }

    @Test
    fun concurrentTapsAndAppEditsAreAllKept() = runTest {
        val (_, binding) = setUp()
        val model = tracker()
        val start = CountDownLatch(1)
        val workers = (1..4).map {
            thread {
                start.await()
                repeat(25) { actions().perform(WidgetTap.Pour, binding) }
            }
        }
        start.countDown()
        repeat(25) { model.addWater() }
        workers.forEach { it.join() }
        assertEquals(125 * 450L, today().waterMillilitres)
        assertEquals(125, reopened().pending.size)
    }

    @Test
    fun stateShowsOnlyThePublishedAccountsDay() {
        directory = folder.newFolder()
        assertEquals(WidgetState.SignedOut, WidgetState.load(directory, now))
        WidgetAccountStore(directory).publish(owner)
        assertEquals(WidgetState.NoChallenge, WidgetState.load(directory, now))
        // Another account's history in the same folder is never shown.
        ChallengeStore(UUID.randomUUID(), directory).start(now, jersey)
        assertEquals(WidgetState.NoChallenge, WidgetState.load(directory, now))
        val store = ChallengeStore(owner, directory)
        store.start(ChallengeCalendar(jersey).addDays(now, -11), jersey)
        store.record(Action.Pour(450), now, now)
        val ready = WidgetState.load(directory, now, Locale.UK) as WidgetState.Ready
        assertEquals(12, ready.dayNumber)
        assertEquals(0, ready.streak)
        assertEquals("8 Oct · Jersey", ready.dateLabel)
        assertEquals(450L, ready.summary.waterMillilitres)
        assertEquals(ChallengeTime.parse("2026-10-08T23:00:00Z"), ready.nextMidnight, 0.0)
        // Damaged history is "Open Daily Challenge", never an empty challenge or a reset.
        store.file.writeText("{")
        assertEquals(WidgetState.Unavailable, WidgetState.load(directory, now))
        assertEquals("Open Daily Challenge to sign in", WidgetState.SignedOut.message)
    }
}

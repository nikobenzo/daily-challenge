package app.dailychallenge.core

import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/** An in-memory server with the real insert-ignore and receipt behaviour (SyncCoordinatorTests.swift). */
class FixtureServer(val now: Double = syncDate) : ChallengeTransport {
    val headers = HashMap<UUID, ChallengeRecord>()
    val events = HashMap<UUID, LinkedHashMap<UUID, ChallengeEvent>>()
    var unavailable = false
    var loseUploadResponse = false
    var requests = 0
    var fetchHook: (() -> Unit)? = null
    var eventsHook: (() -> Unit)? = null

    private fun check() {
        requests++
        if (unavailable) throw NetworkException(IOException("offline"))
    }

    override suspend fun fetchChallenge(ownerID: UUID): ChallengeRecord? {
        check()
        fetchHook.also { fetchHook = null }?.invoke()
        return headers[ownerID]
    }

    override suspend fun insertChallenge(record: ChallengeRecord) {
        check()
        headers.putIfAbsent(record.ownerID, record)
    }

    override suspend fun upload(events: List<ChallengeEvent>, ownerID: UUID) {
        check()
        for (event in events) {
            assertEquals(ownerID, event.ownerID)
            this.events.getOrPut(ownerID) { LinkedHashMap() }.putIfAbsent(event.id,
                event.copy(receivedAt = ChallengeTime.toInstant(now).toString()))
        }
        if (loseUploadResponse) throw NetworkException(IOException("connection lost"))
    }

    override suspend fun fetchEvents(ownerID: UUID, challengeID: UUID): RemoteEvents {
        check()
        val result = events[ownerID]?.values?.toList() ?: emptyList()
        eventsHook.also { eventsHook = null }?.invoke()
        return RemoteEvents(result)
    }
}

class SyncCoordinatorTest {
    @get:Rule val folder = TemporaryFolder()
    private val jersey = ZoneId.of("Europe/Jersey")
    private val owner = UUID.randomUUID()
    private val server = FixtureServer()
    private val today: LocalDate get() = ChallengeCalendar(jersey).localDate(server.now)

    private fun TestScope.model(ownerID: UUID = owner, directory: File = folder.root): Tracker {
        val model = Tracker(directory, this, clock = { server.now }, deviceZone = { jersey })
        model.configureSync(server)
        model.activate(ownerID)
        return model
    }

    @Test
    fun productionSetupRequiresAReachableServerAndAdoptsAnExistingChallenge() = runTest {
        val model = model()
        model.startChallenge(today, jersey)
        assertNull(model.challenge)
        server.unavailable = true
        model.sync()
        assertFalse(model.canStartChallenge)
        assertNotNull(model.syncError)
        assertTrue(model.syncState is SyncState.Unavailable)
        server.unavailable = false
        val header = ChallengeRecord(owner, ChallengeCalendar(jersey).startOfDay(server.now), jersey)
        server.headers[owner] = header
        model.sync(force = true)
        assertEquals(header, model.store!!.record)
        assertEquals(0, model.store!!.pendingCount)
        assertNull(model.syncError)
    }

    @Test
    fun pendingRelaunchLostResponseRetryAndBackendFailureNeverLoseEntries() = runTest {
        val model = model()
        model.sync()
        assertTrue(model.canStartChallenge)
        model.startChallenge(today, jersey)
        model.addWater(); model.addWater()
        server.unavailable = true
        model.sync(force = true)
        assertEquals(900L, model.summary!!.waterMillilitres)
        assertEquals(3, model.store!!.pendingCount)
        val calls = server.requests
        model.sync() // respects backoff
        assertEquals(calls, server.requests)
        val relaunched = model()
        assertEquals(900L, relaunched.summary!!.waterMillilitres)
        server.unavailable = false
        server.loseUploadResponse = true
        relaunched.sync(force = true)
        assertEquals(2, server.events[owner]!!.size)
        assertEquals(3, relaunched.store!!.pendingCount)
        server.loseUploadResponse = false
        relaunched.sync(force = true)
        assertEquals(2, server.events[owner]!!.size)
        assertEquals(0, relaunched.store!!.pendingCount)
        assertTrue(relaunched.syncState is SyncState.Synced)
    }

    @Test
    fun accountSwitchDuringAwaitDiscardsTheStaleResponseAndNeverRelabelsTheQueue() = runTest {
        val model = model()
        model.sync()
        model.startChallenge(today, jersey)
        model.addWater()
        val other = UUID.randomUUID()
        server.fetchHook = { model.activate(other) }
        model.sync(force = true)
        assertEquals(other, model.ownerID)
        assertNull(model.challenge)
        assertNull(server.headers[owner])
        assertNull(server.events[other])
        model.activate(null)
        assertNull(model.store)
        model.activate(owner)
        assertEquals(450L, model.summary!!.waterMillilitres)
        assertEquals(2, model.store!!.pendingCount)
        model.sync(force = true)
        assertEquals(1, server.events[owner]!!.size)
        assertNull(server.events[other])
    }

    @Test
    fun independentOfflineDevicesConvergeHistoryAndStreaks() = runTest {
        val a = model()
        val b = model(directory = File(folder.root, "PhoneB"))
        a.sync(); a.startChallenge(today, jersey); a.addWater()
        a.sync(force = true); b.sync(force = true)
        server.unavailable = true
        a.addCustomWater("4000"); b.addCustomWater("300")
        a.toggle(Habit.WORKOUT); a.toggle(Habit.WALK); a.toggle(Habit.BIBLE_READING); a.setDiet(DietState.CLEAN)
        a.sync(force = true); b.sync(force = true)
        server.unavailable = false
        b.sync(force = true); a.sync(force = true); b.sync(force = true)
        assertEquals(a.challenge!!.allActivities, b.challenge!!.allActivities)
        assertEquals(4750L, a.summary!!.waterMillilitres)
        assertEquals(1, a.streaks!!.current)
        assertEquals(1, b.streaks!!.current)
        assertEquals(0, a.store!!.pendingCount + b.store!!.pendingCount)
    }

    @Test
    fun racedSetupStopsSyncWithoutReplacingEitherHistory() = runTest {
        val a = model()
        val b = model(directory = File(folder.root, "PhoneB"))
        a.sync(); b.sync()
        a.startChallenge(today, jersey); a.addWater()
        b.startChallenge(today.minusDays(1), jersey); b.addCustomWater("900")
        a.sync(force = true); b.sync(force = true)
        assertTrue(b.syncError!!.contains("Different challenges"))
        assertEquals(900L, b.summary!!.waterMillilitres)
        assertEquals(450L, a.summary!!.waterMillilitres)
        assertEquals(2, b.store!!.pendingCount)
        assertEquals(a.store!!.record, server.headers[owner])
        assertEquals(1, server.events[owner]!!.size)
    }

    @Test
    fun editsDuringTheNetworkWaitStayPendingUntilExactServerConfirmation() = runTest {
        val model = model()
        model.sync(); model.startChallenge(today, jersey); model.addWater()
        server.eventsHook = { model.addCustomWater("250") }
        model.sync(force = true)
        assertEquals(700L, model.summary!!.waterMillilitres)
        assertEquals(1, server.events[owner]!!.size)
        assertEquals(1, model.store!!.pendingCount)
        model.sync(force = true)
        assertEquals(2, server.events[owner]!!.size)
        assertEquals(0, model.store!!.pendingCount)
    }

    @Test
    fun historicalCorrectionsNeedEditThisDayAndExtrasFollowTheSelectedDay() = runTest {
        val model = model()
        model.sync(); model.startChallenge(today.minusDays(2), jersey)
        val yesterday = ChallengeCalendar(jersey).startOf(today.minusDays(1))
        model.selectHistoryDay(yesterday)
        assertFalse(model.canEdit)
        model.addWater()
        assertEquals(0L, model.summary!!.waterMillilitres)
        assertTrue(model.errorMessage!!.startsWith("Select Edit this day"))
        model.enableCorrections()
        model.addWater()
        assertEquals(450L, model.summary!!.waterMillilitres)
        assertNull(model.addExtra("  Stretch  "))
        val stretch = model.activeExtras.single()
        assertEquals("Stretch", stretch.title)
        // Added today, so it is not on yesterday's list.
        assertEquals(0, model.summary!!.extrasTotal)
        model.showToday()
        model.toggleExtra(stretch.id)
        assertEquals(setOf(stretch.id), model.summary!!.completedExtras)
        assertTrue(model.activeExtras.isEmpty())
        assertEquals(ChallengeError.INVALID_EXTRA_TITLE.message, model.addExtra("   "))
        model.selectHistoryDay(ChallengeCalendar(jersey).startOf(today.plusDays(1)))
        assertEquals(model.today, model.selectedDay, 0.0) // the future can't be selected
    }

    @Test
    fun customWaterNeedsAPositiveWholeAmountAndStartIsNeverInTheFuture() = runTest {
        val model = model()
        model.sync()
        model.startChallenge(today.plusDays(1), jersey)
        assertEquals("Choose today or an earlier start date.", model.errorMessage)
        model.startChallenge(today, jersey)
        model.addCustomWater("12.5")
        assertEquals("Enter a positive whole amount in ml, such as 250.", model.errorMessage)
        model.addCustomWater(" 250 ")
        assertEquals(250L, model.summary!!.waterMillilitres)
        assertEquals(1, model.dayNumber)
    }

    @Test
    fun removingLocalDataSignsTheTrackerOutAndKeepsOtherAccounts() = runTest {
        val model = model()
        model.sync(); model.startChallenge(today, jersey); model.addWater()
        val other = model(ownerID = UUID.randomUUID())
        other.sync(); other.startChallenge(today, jersey)
        model.removeLocalData(owner)
        assertNull(model.store)
        assertFalse(File(folder.root, ChallengeStore.fileName(owner)).exists())
        assertTrue(File(folder.root, ChallengeStore.fileName(other.ownerID!!)).exists())
    }
}

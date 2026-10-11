package app.dailychallenge.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.ZoneId
import java.util.UUID

private val jersey: ZoneId = ZoneId.of("Europe/Jersey")
val syncDate: Double = ChallengeTime.fromUnix(1_791_460_800.0)

fun confirmed(events: List<ChallengeEvent>, at: Double = syncDate): List<ChallengeEvent> =
    events.map { it.copy(receivedAt = ChallengeTime.toInstant(at).toString()) }

fun <T> assertThrowsAny(block: () -> T) {
    try {
        block()
    } catch (_: Exception) {
        return
    }
    throw AssertionError("Expected an exception")
}

/** Ports of ChallengeStoreTests.swift and the store cases of ChallengeSyncTests.swift. */
class ChallengeStoreTest {
    @get:Rule val folder = TemporaryFolder()

    private val now = ChallengeTime.parse("2026-10-08T12:00:00Z")

    @Test
    fun allFiveRequirementsAndCorrectionsSurviveRelaunch() {
        val owner = UUID.randomUUID()
        val directory = folder.newFolder()
        val store = ChallengeStore(owner, directory)
        assertNull(store.challenge)
        store.start(now, jersey)
        store.record(Action.Pour(4_000), now, now)
        Habit.entries.forEach { store.record(Action.SetHabit(it, true), now, now) }
        store.record(Action.SetDiet(DietState.CLEAN), now, now)
        store.record(Action.SetDiet(DietState.MISSED), now, now)
        store.record(Action.SetDiet(DietState.CLEAN), now, now)
        val reopened = ChallengeStore(owner, directory).challenge!!
        assertTrue(reopened.summary(now, now).isComplete)
        assertEquals(1, reopened.streaks(now).current)
        assertEquals(7, reopened.history(now).size)
        // Repeated clock values still keep local order: ordered IDs follow each other.
        assertEquals(store.challenge!!.allActivities, reopened.allActivities)
    }

    @Test
    fun duplicatedActivityInASavedFileIsRejectedRatherThanDoubleCounted() {
        val owner = UUID.randomUUID()
        val directory = folder.newFolder()
        val store = ChallengeStore(owner, directory)
        store.start(now, jersey)
        store.record(Action.Pour(450), now, now)
        val envelope = Wire.json.parseToJsonElement(store.file.readText()).jsonObject
        val saved = envelope.getValue("challenge").jsonObject
        val activities = saved.getValue("activities").jsonArray
        val damaged = JsonObject(envelope + ("challenge" to JsonObject(saved + ("activities" to JsonArray(activities + activities)))))
        store.file.writeText(Wire.text(damaged))
        assertThrowsAny { ChallengeStore(owner, directory) }
        assertEquals(450L, store.challenge!!.summary(now, now).waterMillilitres)
    }

    @Test
    fun aFailedWritePreservesThePreviouslySavedDayAndLiveState() {
        val owner = UUID.randomUUID()
        val directory = folder.newFolder()
        val store = ChallengeStore(owner, directory)
        store.start(now, jersey)
        store.record(Action.Pour(450), now, now)
        directory.setWritable(false)
        try {
            assertThrowsAny { store.record(Action.Pour(450), now, now) }
            assertEquals(450L, store.challenge!!.summary(now, now).waterMillilitres)
        } finally {
            directory.setWritable(true)
        }
        assertEquals(450L, ChallengeStore(owner, directory).challenge!!.summary(now, now).waterMillilitres)
    }

    @Test
    fun localHistoryIsSeparatedByAccountAndSetupCannotReplaceIt() {
        val directory = folder.newFolder()
        val first = ChallengeStore(UUID.randomUUID(), directory)
        assertThrowsAny { first.record(Action.Pour(450), now, now) }
        first.start(now, jersey)
        first.record(Action.Pour(450), now, now)
        val secondOwner = UUID.randomUUID()
        val second = ChallengeStore(secondOwner, directory)
        assertNull(second.challenge)
        second.start(now, jersey)
        second.record(Action.Pour(900), now, now)
        assertThrowsAny { first.start(now + 86_400, jersey) }
        assertEquals(900L, ChallengeStore(secondOwner, directory).challenge!!.summary(now, now).waterMillilitres)
        assertEquals(450L, first.challenge!!.summary(now, now).waterMillilitres)
    }

    @Test
    fun unreadableSavedDataIsPreservedRatherThanReplaced() {
        val owner = UUID.randomUUID()
        val directory = folder.newFolder()
        ChallengeStore(owner, directory).start(now, jersey)
        java.io.File(directory, ChallengeStore.fileName(owner)).writeText("broken json")
        assertThrowsAny { ChallengeStore(owner, directory) }
        assertThrowsAny { ChallengeStore(owner, directory) }
        assertEquals("broken json", java.io.File(directory, ChallengeStore.fileName(owner)).readText())
    }

    @Test
    fun twoOfflineDevicesMergeAdditionsAndDuplicateUndoWithoutResurrection() {
        val owner = UUID.randomUUID()
        val aDir = folder.newFolder()
        val a = ChallengeStore(owner, aDir)
        val b = ChallengeStore(owner, folder.newFolder())
        a.start(syncDate, jersey)
        a.record(Action.Pour(450), syncDate, syncDate)
        a.record(Action.Pour(450), syncDate, syncDate + 1)
        val header = a.record!!
        val initial = confirmed(a.pending)
        a.merge(header, initial)
        b.merge(header, initial)
        a.record(Action.UndoLatestPour, syncDate, syncDate + 2)
        b.record(Action.UndoLatestPour, syncDate, syncDate + 3)
        a.record(Action.Pour(200), syncDate, syncDate + 4)
        b.record(Action.Pour(300), syncDate, syncDate + 5)
        val union = confirmed(a.pending + b.pending)
        a.merge(header, union.reversed())
        b.merge(header, union + initial + union)
        assertEquals(a.challenge!!.allActivities, b.challenge!!.allActivities)
        assertEquals(950L, a.challenge!!.summary(syncDate, syncDate).waterMillilitres)
        assertEquals(0, a.pendingCount + b.pendingCount)
        a.merge(header, initial) // a stale snapshot cannot resurrect the undone pour
        val reopened = ChallengeStore(owner, aDir)
        assertEquals(b.challenge!!.allActivities, reopened.challenge!!.allActivities)
    }

    @Test
    fun clockWarningClearsOnTheNextCleanMergeAndIgnoresRefetchedHistory() {
        val owner = UUID.randomUUID()
        val directory = folder.newFolder()
        val store = ChallengeStore(owner, directory)
        store.start(syncDate, jersey)
        store.record(Action.Pour(450), syncDate, syncDate)
        val header = store.record!!
        val ahead = confirmed(store.pending, syncDate - 301)
        store.merge(header, ahead)
        assertTrue(store.hasClockWarning)
        assertTrue(ChallengeStore(owner, directory).hasClockWarning)
        store.record(Action.Pour(450), syncDate, syncDate + 60)
        val late = confirmed(store.pending, syncDate + 3600)
        store.merge(header, ahead + late)
        assertFalse(store.hasClockWarning)
        assertFalse(ChallengeStore(owner, directory).hasClockWarning)
    }

    @Test
    fun acknowledgmentRequiresMatchingImmutableContentsAndOwner() {
        val owner = UUID.randomUUID()
        val directory = folder.newFolder()
        val store = ChallengeStore(owner, directory)
        store.start(syncDate, jersey)
        val id = UUID.randomUUID()
        store.record(Action.Pour(450), syncDate, syncDate, id)
        store.record(Action.Pour(450), syncDate, syncDate, id)
        val header = store.record!!
        val event = store.pending.first()
        val conflicting = event.activity.copy(action = Action.Pour(900))
        assertThrowsAny { store.merge(header, confirmed(listOf(ChallengeEvent(owner, header.id, conflicting)))) }
        assertThrowsAny { store.merge(header, confirmed(listOf(ChallengeEvent(UUID.randomUUID(), header.id, event.activity)))) }
        assertThrowsAny { store.merge(header, listOf(event)) } // no server receipt
        assertEquals(2, store.pendingCount)
        assertEquals(2, ChallengeStore(owner, directory).pendingCount)
        store.merge(header, confirmed(listOf(event)))
        assertEquals(0, store.pendingCount)
    }

    @Test
    fun differingChallengesNeverReplaceLocalHistoryIncludingAZoneOnlyDifference() {
        val owner = UUID.randomUUID()
        val directory = folder.newFolder()
        val store = ChallengeStore(owner, directory)
        store.start(syncDate, jersey)
        store.record(Action.Pour(900), syncDate, syncDate)
        val original = store.record!!
        val before = store.file.readText()
        assertThrowsAny { store.merge(ChallengeRecord(owner, original.startDate, jersey), emptyList()) }
        val london = original.copy(timeZone = "Europe/London")
        try {
            store.merge(london, emptyList())
            throw AssertionError("merged")
        } catch (error: ChallengeSyncException) {
            assertEquals(ChallengeSyncError.CONFLICTING_CHALLENGE, error.error)
        }
        assertEquals(before, store.file.readText())
        assertEquals(original, ChallengeStore(owner, directory).record)
    }

    @Test
    fun anEmptyDeviceAdoptsTheServersZoneAndRefusesAnImpossibleRecord() {
        val owner = UUID.randomUUID()
        val sydney = ZoneId.of("Australia/Sydney")
        val start = ChallengeCalendar(sydney).startOf(java.time.LocalDate.of(2026, 10, 8)) + 1800
        val a = ChallengeStore(owner, folder.newFolder())
        a.start(start, sydney)
        a.record(Action.Pour(450), start, start)
        val record = a.record!!
        assertEquals("Australia/Sydney", record.timeZone)
        val bDir = folder.newFolder()
        val b = ChallengeStore(owner, bDir)
        b.merge(record, confirmed(a.pending, start))
        assertEquals(sydney, b.challenge!!.zone)
        assertEquals(450L, b.challenge!!.summary(start, start).waterMillilitres)
        assertEquals(record, ChallengeStore(owner, bDir).record)
        val invalid = ChallengeStore(owner, folder.newFolder())
        assertThrowsAny { invalid.merge(record.copy(id = UUID.randomUUID(), timeZone = "Bogus/Zone"), emptyList()) }
        assertNull(invalid.challenge)
    }

    @Test
    fun pendingEventsUseTheWireFormatAndTheSnapshotKeepsTheAppleShape() {
        val owner = UUID.randomUUID()
        val store = ChallengeStore(owner, folder.newFolder())
        store.start(syncDate, jersey)
        store.record(Action.Pour(450), syncDate, syncDate)
        val event = store.pending.single()
        val body = Wire.text(Wire.encode(event))
        assertTrue(body.startsWith("{\"id\":\"${Challenge.uuidString(event.id)}\",\"activity\":{"))
        assertTrue(body.endsWith(",\"owner_id\":\"${Challenge.uuidString(owner)}\",\"challenge_id\":\"${Challenge.uuidString(store.record!!.id)}\"}"))
        val snapshot = Wire.json.parseToJsonElement(store.file.readText()).jsonObject
        assertEquals(setOf("challenge", "clockWarning", "deviceID", "headerPending", "pendingIDs", "record", "version"), snapshot.keys)
        assertEquals(JsonPrimitive(2), snapshot["version"])
        assertEquals(2, store.pendingCount) // the event and the challenge settings
    }

    @Test
    fun removingAccountFilesLeavesOtherAccounts() {
        val directory = folder.newFolder()
        val gone = UUID.randomUUID()
        val kept = UUID.randomUUID()
        ChallengeStore(gone, directory).start(now, jersey)
        ChallengeStore(kept, directory).start(now, jersey)
        java.io.File(directory, CelebrationLedger.fileName(gone)).writeText("[]")
        ChallengeStore.removeAccountFiles(gone, directory)
        assertEquals(listOf(ChallengeStore.fileName(kept)), directory.list()!!.toList())
    }
}

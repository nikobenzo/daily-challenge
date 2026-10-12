package app.dailychallenge.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID

enum class ChallengeStoreError(val message: String) {
    NOT_STARTED("Select a challenge start date first."),
    ALREADY_STARTED("This account already has a challenge. Existing history was not replaced."),
    WRONG_OWNER("The saved challenge belongs to another account. It has not been reset."),
    UNSUPPORTED_VERSION("The saved challenge uses an unsupported format. It has not been reset."),
}

class ChallengeStoreException(val error: ChallengeStoreError) : Exception(error.message)

enum class ChallengeSyncError(val message: String) {
    SERVER_NEEDS_TIME_ZONE_UPDATE("The server needs the timezone update before this challenge can sync. Your entries are safe on this phone."),
    CONFLICTING_CHALLENGE("Different challenges were found for this account. Sync stopped; both histories are preserved."),
    INVALID_RECORD("A challenge sync record is invalid or conflicts with saved history. Nothing was replaced."),
    WRONG_OWNER("The sync session or record belongs to another account. Nothing was merged."),
}

class ChallengeSyncException(val error: ChallengeSyncError) : Exception(error.message)

/**
 * One serialized writer per account (Swift `ChallengeStore`). History and its outbound queue
 * commit in one atomic file, including acknowledgments. No network is needed to record.
 * The file is the same version-2 snapshot shape the Apple apps write.
 */
class ChallengeStore(private val ownerID: UUID, directory: File) {
    private data class Snapshot(
        val challenge: Challenge,
        val record: ChallengeRecord,
        val deviceID: String,
        val pendingIDs: Set<UUID>,
        val headerPending: Boolean,
        val clockWarning: Boolean,
    )

    val file = File(directory, fileName(ownerID))
    private var snapshot: Snapshot? = null

    val challenge: Challenge? get() = snapshot?.challenge
    val record: ChallengeRecord? get() = snapshot?.record
    val deviceID: String? get() = snapshot?.deviceID
    val hasClockWarning: Boolean get() = snapshot?.clockWarning ?: false
    val pendingCount: Int get() = pending.size + if (snapshot?.headerPending == true) 1 else 0

    /** Unsynced events in event order, ready to upload. */
    val pending: List<ChallengeEvent>
        get() {
            val current = snapshot ?: return emptyList()
            return current.challenge.allActivities.filter { it.id in current.pendingIDs }
                .map { ChallengeEvent(ownerID, current.record.id, it) }
        }

    init {
        if (file.exists()) snapshot = decode(file.readText())
    }

    /**
     * Targets other than the standard five become one `setWater` or `setTarget` event per changed
     * value, dated the start day and committed with the settings, so setup is never half
     * written. `at` is when they are recorded.
     */
    fun start(on: Double, zone: java.time.ZoneId, targets: Targets = Targets.STANDARD, at: Double = ChallengeTime.now()) {
        if (snapshot != null) throw ChallengeStoreException(ChallengeStoreError.ALREADY_STARTED)
        if (Challenge.canonicalZone(zone.id) == null) throw ChallengeSyncException(ChallengeSyncError.INVALID_RECORD)
        val challenge = Challenge(ownerID, on, zone)
        var next = Snapshot(challenge, ChallengeRecord(ownerID, challenge.startDate, zone), Challenge.uuidString(UUID.randomUUID()),
            emptySet(), headerPending = true, clockWarning = false)
        for (action in targets.changes()) {
            val id = nextID(at, next)
            next.challenge.record(action, challenge.startDate, at, id, next.deviceID)
            next = next.copy(pendingIDs = next.pendingIDs + id)
        }
        commit(next)
    }

    fun record(action: Action, on: Double, at: Double, id: UUID? = null): UUID? {
        val current = snapshot ?: throw ChallengeStoreException(ChallengeStoreError.NOT_STARTED)
        // Ordered IDs preserve explicit local order when the clock repeats a value for
        // consecutive edits. Distributed ordering still uses (timestamp, device, event ID).
        val eventID = id ?: nextID(at, current)
        val next = current.challenge.copy()
        val result = next.record(action, on, at, eventID, current.deviceID) ?: return null
        val pending = if (current.challenge.allActivities.none { it.id == result }) current.pendingIDs + result else current.pendingIDs
        commit(current.copy(challenge = next, pendingIDs = pending))
        return result
    }

    fun merge(remote: ChallengeRecord, events: List<ChallengeEvent>) {
        if (remote.ownerID != ownerID) throw ChallengeSyncException(ChallengeSyncError.WRONG_OWNER)
        val adopted = remote.emptyChallenge() ?: throw ChallengeSyncException(ChallengeSyncError.INVALID_RECORD)
        snapshot?.let { if (it.record != remote) throw ChallengeSyncException(ChallengeSyncError.CONFLICTING_CHALLENGE) }
        val current = snapshot ?: Snapshot(adopted, remote, Challenge.uuidString(UUID.randomUUID()), emptySet(),
            headerPending = false, clockWarning = false)
        for (event in events) {
            if (event.ownerID != ownerID) throw ChallengeSyncException(ChallengeSyncError.WRONG_OWNER)
            if (event.challengeID != remote.id || event.id != event.activity.id ||
                event.activity.deviceID.isNullOrEmpty() || event.receiptDate == null
            ) throw ChallengeSyncException(ChallengeSyncError.INVALID_RECORD)
        }
        val next = current.challenge.copy()
        next.merge(events.map { it.activity })
        // Every sync refetches the full history, so the warning reflects only this phone's
        // uploads that this merge acknowledges, and clears on the next clean one.
        val acknowledged = events.filter { it.id in current.pendingIDs }
        commit(current.copy(challenge = next, pendingIDs = current.pendingIDs - events.map { it.id }.toSet(),
            headerPending = false, clockWarning = acknowledged.any { it.hasClockWarning }))
    }

    private fun nextID(at: Double, current: Snapshot): UUID {
        val last = current.challenge.allActivities.filter { it.recordedAt == at && it.deviceID == current.deviceID }
            .map { it.id }.maxByOrNull { Challenge.uuidString(it) } ?: return UUID.randomUUID()
        val bytes = java.nio.ByteBuffer.allocate(16).putLong(last.mostSignificantBits).putLong(last.leastSignificantBits).array()
        for (index in bytes.indices.reversed()) {
            if (bytes[index] != 0xFF.toByte()) {
                bytes[index] = (bytes[index] + 1).toByte()
                break
            }
            bytes[index] = 0
        }
        val buffer = java.nio.ByteBuffer.wrap(bytes)
        return UUID(buffer.long, buffer.long)
    }

    private fun commit(next: Snapshot) {
        file.parentFile?.mkdirs()
        val temporary = File(file.parentFile, "${file.name}.${UUID.randomUUID()}.tmp")
        try {
            temporary.writeText(encode(next))
            Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally {
            temporary.delete()
        }
        snapshot = next
    }

    private fun encode(value: Snapshot): String = Wire.text(JsonObject(linkedMapOf(
        "challenge" to JsonObject(linkedMapOf(
            "activities" to JsonArray(value.challenge.allActivities.map(Wire::encode)),
            "ownerID" to Wire.uuid(ownerID),
            "startDate" to Wire.number(value.challenge.startDate),
            "timeZone" to JsonPrimitive(value.challenge.zone.id),
        )),
        "clockWarning" to JsonPrimitive(value.clockWarning),
        "deviceID" to JsonPrimitive(value.deviceID),
        "headerPending" to JsonPrimitive(value.headerPending),
        "pendingIDs" to JsonArray(value.pendingIDs.map(Wire::uuid)),
        "record" to Wire.encode(value.record),
        "version" to JsonPrimitive(2),
    )))

    /** Loading must obey the same rules as recording: a damaged file throws, never resets. */
    private fun decode(text: String): Snapshot {
        val root = Wire.json.parseToJsonElement(text) as? JsonObject ?: throw invalid()
        if ((root["version"] as? JsonPrimitive)?.content != "2") throw ChallengeStoreException(ChallengeStoreError.UNSUPPORTED_VERSION)
        val saved = root["challenge"] as? JsonObject ?: throw invalid()
        val owner = Wire.uuidOf(saved["ownerID"], "ownerID")
        if (owner != ownerID) throw ChallengeStoreException(ChallengeStoreError.WRONG_OWNER)
        val zone = Challenge.canonicalZone(Wire.stringOf(saved["timeZone"], "timeZone")) ?: throw invalid()
        val start = Wire.doubleOf(saved["startDate"], "startDate")
        val challenge = Challenge(owner, start, zone)
        if (challenge.startDate != start) throw invalid()
        val activities = (saved["activities"] as? JsonArray ?: throw invalid()).map(Wire::decodeActivity)
        if (activities.map { it.id }.toSet().size != activities.size) throw invalid()
        if (activities.any { it.deviceID.isNullOrEmpty() }) throw invalid()
        challenge.merge(activities)
        val record = Wire.decodeRecord(root["record"] ?: throw invalid())
        val deviceID = Wire.stringOf(root["deviceID"], "deviceID")
        val pending = (root["pendingIDs"] as? JsonArray ?: throw invalid()).map { Wire.uuidOf(it, "pending ID") }.toSet()
        if (record.ownerID != ownerID || record.startDate != challenge.startDate || record.timeZone != zone.id ||
            deviceID.isEmpty() || !activities.map { it.id }.toSet().containsAll(pending)
        ) throw invalid()
        return Snapshot(challenge, record, deviceID, pending, Wire.boolOf(root["headerPending"], "headerPending"),
            Wire.boolOf(root["clockWarning"], "clockWarning"))
    }

    private fun invalid() = ChallengeSyncException(ChallengeSyncError.INVALID_RECORD)

    companion object {
        fun fileName(ownerID: UUID): String = "challenge-${ownerID.toString().lowercase()}.json"

        /** After the account is deleted: this owner's history, queue and celebration ledger. */
        fun removeAccountFiles(ownerID: UUID, directory: File) {
            val owner = ownerID.toString().lowercase()
            directory.listFiles()?.forEach { file ->
                val name = file.name.lowercase()
                if (name.startsWith("challenge-$owner.json") || name == "celebrations-$owner.json") {
                    if (!file.delete()) throw java.io.IOException("Could not remove ${file.name}")
                }
            }
        }
    }
}


package app.dailychallenge.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import java.time.OffsetDateTime
import java.util.UUID

class WireException(message: String) : Exception(message)

/**
 * The JSON every client and the server share, written exactly as Swift's synthesized
 * `Codable` writes it (same keys, same key order, upper-case UUIDs, whole numbers without a
 * decimal point), and read as strictly as Swift reads it, so a row one client refuses is
 * refused by all of them:
 *
 *     {"pour":{"_0":450}}                 {"undoLatestPour":{}}
 *     {"setHabit":{"_0":"walk","completed":true}}    {"setDiet":{"_0":"clean"}}
 *     {"defineExtra":{"id":"<UUID>","title":"Stretch"}}
 *     {"archiveExtra":{"id":"<UUID>"}}    {"setExtra":{"id":"<UUID>","completed":true}}
 *     {"setTarget":{"_0":"walk","name":"Yoga","amount":30,"unit":"minutes","icon":"yoga"}}
 *     {"setTarget":{"_0":"diet","name":"No sugar"}}    {"setWater":{"goal":3000,"pour":250}}
 *     {"scheduleExtra":{"id":"<UUID>","weekdays":[1,2,3,4,5]}}
 *     {"scheduleExtra":{"id":"<UUID>","every":2}}      {"scheduleExtra":{"id":"<UUID>"}}
 *
 * Absent values are left out, and null reads as absent. A target or schedule outside the
 * shared rules ([contentError]) is unreadable, like an unknown kind.
 */
object Wire {
    val json = Json { prettyPrint = false }

    // MARK: Writing

    /** Compact JSON text of `element`, numbers as [number] writes them. */
    fun text(element: JsonElement, sortKeys: Boolean = false): String =
        StringBuilder().also { write(element, it, sortKeys) }.toString()

    private fun write(element: JsonElement, out: StringBuilder, sortKeys: Boolean) {
        when (element) {
            is JsonObject -> {
                out.append('{')
                val entries = if (sortKeys) element.entries.sortedBy { it.key } else element.entries.toList()
                entries.forEachIndexed { index, (key, value) ->
                    if (index > 0) out.append(',')
                    out.append(JsonPrimitive(key).toString()).append(':')
                    write(value, out, sortKeys)
                }
                out.append('}')
            }
            is JsonArray -> {
                out.append('[')
                element.forEachIndexed { index, value ->
                    if (index > 0) out.append(',')
                    write(value, out, sortKeys)
                }
                out.append(']')
            }
            // Swift's JSONEncoder escapes "/" ("Europe\/Jersey"); readers see the same string.
            is JsonPrimitive -> out.append(if (element.isString) element.toString().replace("/", "\\/") else element.toString())
        }
    }

    /** Whole values as integers ("781484400"), others in plain shortest form. */
    fun number(value: Double): JsonPrimitive {
        require(value.isFinite()) { "JSON numbers must be finite" }
        if (value == Math.floor(value) && Math.abs(value) < 1e15) return JsonPrimitive(value.toLong())
        return JsonPrimitive(BigDecimal(value.toString()).toPlainString().toBigDecimal())
    }

    fun uuid(id: UUID): JsonPrimitive = JsonPrimitive(Challenge.uuidString(id))

    private fun obj(vararg pairs: Pair<String, JsonElement>): JsonObject = JsonObject(linkedMapOf(*pairs))

    fun encode(action: Action): JsonObject = when (action) {
        is Action.Pour -> obj("pour" to obj("_0" to JsonPrimitive(action.millilitres)))
        Action.UndoLatestPour -> obj("undoLatestPour" to obj())
        is Action.SetHabit -> obj("setHabit" to obj("_0" to JsonPrimitive(action.habit.wire), "completed" to JsonPrimitive(action.completed)))
        is Action.SetDiet -> obj("setDiet" to obj("_0" to JsonPrimitive(action.state.wire)))
        is Action.DefineExtra -> obj("defineExtra" to obj("id" to uuid(action.id), "title" to JsonPrimitive(action.title)))
        is Action.ArchiveExtra -> obj("archiveExtra" to obj("id" to uuid(action.id)))
        is Action.SetExtra -> obj("setExtra" to obj("id" to uuid(action.id), "completed" to JsonPrimitive(action.completed)))
        is Action.SetTarget -> obj("setTarget" to JsonObject(buildMap {
            put("_0", JsonPrimitive(action.slot.wire))
            put("name", JsonPrimitive(action.name))
            action.amount?.let { put("amount", JsonPrimitive(it)) }
            action.unit?.let { put("unit", JsonPrimitive(it.wire)) }
            action.icon?.let { put("icon", JsonPrimitive(it)) }
        }))
        is Action.SetWater -> obj("setWater" to obj("goal" to JsonPrimitive(action.goal), "pour" to JsonPrimitive(action.pour)))
        is Action.ScheduleExtra -> obj("scheduleExtra" to JsonObject(buildMap {
            put("id", uuid(action.id))
            action.weekdays?.let { days -> put("weekdays", JsonArray(days.map { JsonPrimitive(it) })) }
            action.every?.let { put("every", JsonPrimitive(it)) }
        }))
    }

    fun encode(activity: Activity): JsonObject {
        val values = linkedMapOf<String, JsonElement>(
            "id" to uuid(activity.id),
            "day" to number(activity.day),
            "recordedAt" to number(activity.recordedAt),
            "action" to encode(activity.action),
        )
        activity.undonePourID?.let { values["undonePourID"] = uuid(it) }
        activity.deviceID?.let { values["deviceID"] = JsonPrimitive(it) }
        return JsonObject(values)
    }

    fun encode(record: ChallengeRecord): JsonObject = obj(
        "id" to uuid(record.id),
        "owner_id" to uuid(record.ownerID),
        "start_time" to number(record.startTime),
        "time_zone" to JsonPrimitive(record.timeZone),
    )

    /** The upload body: `received_at` is the server's to write, so it is left out when absent. */
    fun encode(event: ChallengeEvent): JsonObject {
        val values = linkedMapOf<String, JsonElement>(
            "id" to uuid(event.id),
            "activity" to encode(event.activity),
            "owner_id" to uuid(event.ownerID),
            "challenge_id" to uuid(event.challengeID),
        )
        event.receivedAt?.let { values["received_at"] = JsonPrimitive(it) }
        return JsonObject(values)
    }

    // MARK: Reading

    private fun fail(message: String): Nothing = throw WireException(message)

    private fun JsonElement.asObject(what: String): JsonObject = this as? JsonObject ?: fail("$what is not an object")

    private fun JsonObject.required(key: String): JsonElement =
        this[key]?.takeUnless { it is JsonNull } ?: fail("Missing $key")

    fun uuidOf(element: JsonElement?, what: String): UUID {
        val text = (element as? JsonPrimitive)?.takeIf { it.isString }?.content ?: fail("$what is not a UUID string")
        return parseUUID(text) ?: fail("$what is not a UUID")
    }

    private val uuidPattern = Regex("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    /** Swift `UUID(uuidString:)`: the hyphenated form, either case. */
    fun parseUUID(text: String): UUID? = if (uuidPattern.matches(text)) UUID.fromString(text) else null

    fun doubleOf(element: JsonElement?, what: String): Double {
        val primitive = element as? JsonPrimitive ?: fail("$what is not a number")
        if (primitive.isString || primitive is JsonNull) fail("$what is not a number")
        val content = primitive.content
        if (content == "true" || content == "false") fail("$what is not a number")
        return content.toDoubleOrNull()?.takeIf { it.isFinite() } ?: fail("$what is not a number")
    }

    private val integerPattern = Regex("-?(0|[1-9][0-9]*)")

    fun longOf(element: JsonElement?, what: String): Long {
        val primitive = element as? JsonPrimitive ?: fail("$what is not an integer")
        if (primitive.isString || !integerPattern.matches(primitive.content)) fail("$what is not an integer")
        return primitive.content.toLongOrNull() ?: fail("$what does not fit")
    }

    fun boolOf(element: JsonElement?, what: String): Boolean {
        val primitive = element as? JsonPrimitive ?: fail("$what is not a Boolean")
        if (primitive.isString) fail("$what is not a Boolean")
        return when (primitive.content) {
            "true" -> true
            "false" -> false
            else -> fail("$what is not a Boolean")
        }
    }

    fun stringOf(element: JsonElement?, what: String): String {
        val primitive = element as? JsonPrimitive ?: fail("$what is not a string")
        if (!primitive.isString) fail("$what is not a string")
        return primitive.content
    }

    /** Exactly one known key, as Swift's synthesized enum decoding requires. Extra inner keys are ignored. */
    fun decodeAction(element: JsonElement): Action {
        val outer = element.asObject("action")
        if (outer.size != 1) fail("An action has exactly one key")
        val (kind, value) = outer.entries.first()
        val inner = value.asObject(kind)
        return when (kind) {
            "pour" -> Action.Pour(longOf(inner["_0"], "pour"))
            "undoLatestPour" -> Action.UndoLatestPour
            "setHabit" -> Action.SetHabit(
                Habit.fromWire(stringOf(inner["_0"], "habit")) ?: fail("Unknown habit"),
                boolOf(inner["completed"], "completed"),
            )
            "setDiet" -> Action.SetDiet(DietState.fromWire(stringOf(inner["_0"], "diet")) ?: fail("Unknown diet state"))
            "defineExtra" -> Action.DefineExtra(uuidOf(inner["id"], "extra id"), stringOf(inner["title"], "title"))
            "archiveExtra" -> Action.ArchiveExtra(uuidOf(inner["id"], "extra id"))
            "setExtra" -> Action.SetExtra(uuidOf(inner["id"], "extra id"), boolOf(inner["completed"], "completed"))
            "setTarget" -> Action.SetTarget(
                TargetSlot.fromWire(stringOf(inner["_0"], "slot")) ?: fail("Unknown slot"),
                stringOf(inner["name"], "name"),
                inner.optional("amount")?.let { longOf(it, "amount") },
                inner.optional("unit")?.let { TargetUnit.fromWire(stringOf(it, "unit")) ?: fail("Unknown unit") },
                inner.optional("icon")?.let { stringOf(it, "icon") },
            )
            "setWater" -> Action.SetWater(longOf(inner["goal"], "goal"), longOf(inner["pour"], "pour"))
            "scheduleExtra" -> Action.ScheduleExtra(
                uuidOf(inner["id"], "extra id"),
                inner.optional("weekdays")?.let { days -> (days as? JsonArray ?: fail("weekdays is not an array")).map { longOf(it, "weekday") } },
                inner.optional("every")?.let { longOf(it, "every") },
            )
            else -> fail("Unknown action $kind")
        }
    }

    /** Swift's `decodeIfPresent`: a missing key and null are both absent. */
    private fun JsonObject.optional(key: String): JsonElement? = this[key]?.takeUnless { it is JsonNull }

    fun decodeActivity(element: JsonElement): Activity {
        val values = element.asObject("activity")
        val action = decodeAction(values.required("action"))
        // Unreadable, like an unknown kind: sync skips the row, so it never fails a merge.
        if (action.contentError != null) fail("Invalid target or schedule")
        return Activity(
            id = uuidOf(values["id"], "id"),
            day = doubleOf(values["day"], "day"),
            recordedAt = doubleOf(values["recordedAt"], "recordedAt"),
            action = action,
            undonePourID = values["undonePourID"]?.takeUnless { it is JsonNull }?.let { uuidOf(it, "undonePourID") },
            deviceID = values["deviceID"]?.takeUnless { it is JsonNull }?.let { stringOf(it, "deviceID") },
        )
    }

    /** A server without the timezone migration, or an older record, has no zone: Jersey days. */
    fun decodeRecord(element: JsonElement): ChallengeRecord {
        val values = element.asObject("challenge")
        return ChallengeRecord(
            id = uuidOf(values["id"], "id"),
            ownerID = uuidOf(values["owner_id"], "owner_id"),
            startTime = doubleOf(values["start_time"], "start_time"),
            timeZone = values["time_zone"]?.takeUnless { it is JsonNull }?.let { stringOf(it, "time_zone") }
                ?: Challenge.LEGACY_TIME_ZONE_ID,
        )
    }

    fun decodeEvent(element: JsonElement): ChallengeEvent {
        val values = element.asObject("event")
        return ChallengeEvent(
            id = uuidOf(values["id"], "id"),
            ownerID = uuidOf(values["owner_id"], "owner_id"),
            challengeID = uuidOf(values["challenge_id"], "challenge_id"),
            activity = decodeActivity(values.required("activity")),
            receivedAt = values["received_at"]?.takeUnless { it is JsonNull }?.let { stringOf(it, "received_at") },
        )
    }
}

/** Immutable account challenge settings (Swift `ChallengeRecord`). `startTime` is Unix seconds. */
data class ChallengeRecord(val id: UUID, val ownerID: UUID, val startTime: Double, val timeZone: String) {
    constructor(ownerID: UUID, startDate: Double, zone: java.time.ZoneId, id: UUID = UUID.randomUUID()) :
        this(id, ownerID, ChallengeTime.toUnix(startDate), zone.id)

    /** Reference seconds, like every other instant in the rules. */
    val startDate: Double get() = ChallengeTime.fromUnix(startTime)

    /** The challenge these settings describe, or null for an impossible start or zone. */
    fun emptyChallenge(): Challenge? {
        if (!startTime.isFinite()) return null
        val zone = Challenge.canonicalZone(timeZone) ?: return null
        val challenge = Challenge(ownerID, startDate, zone)
        return if (challenge.startDate == startDate) challenge else null
    }
}

/** One synced event row (Swift `ChallengeEvent`); `id` is always the activity's. */
data class ChallengeEvent(
    val id: UUID,
    val ownerID: UUID,
    val challengeID: UUID,
    val activity: Activity,
    val receivedAt: String? = null,
) {
    constructor(ownerID: UUID, challengeID: UUID, activity: Activity, receivedAt: String? = null) :
        this(activity.id, ownerID, challengeID, activity, receivedAt)

    /** The server's receipt time in reference seconds, or null when absent or unreadable. */
    val receiptDate: Double?
        get() = receivedAt?.let {
            try {
                ChallengeTime.fromInstant(OffsetDateTime.parse(it).toInstant())
            } catch (_: Exception) {
                null
            }
        }

    /**
     * True when the entry was recorded more than five minutes after the server received it,
     * so the recording clock must be ahead of the server's. Late delivery is expected.
     */
    val hasClockWarning: Boolean
        get() {
            val receipt = receiptDate ?: return false
            return activity.recordedAt - receipt > 300
        }
}

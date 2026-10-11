package app.dailychallenge.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.util.UUID

/**
 * The shared vectors in test-vectors/challenge-rules.json, which
 * Tests/ChallengeCoreTests/ParityVectorTests.swift proves against ChallengeCore. Passing
 * here means the Android rules and wire format give the Mac's and iPhone's results.
 */
class ParityVectorTest {
    private val vectors: JsonObject = Wire.json.parseToJsonElement(
        File(System.getProperty("parityVectors") ?: "../../test-vectors", "challenge-rules.json").readText(),
    ).jsonObject

    private fun list(key: String) = vectors.getValue(key).jsonArray.map { it.jsonObject }

    private fun instant(value: JsonElement?): Double {
        val primitive = value!!.jsonPrimitive
        return if (primitive.isString) ChallengeTime.parse(primitive.content) else primitive.content.toDouble()
    }

    private fun uuid(value: JsonElement?): UUID = UUID.fromString(value!!.jsonPrimitive.content)
    private fun uuids(value: JsonElement?): List<UUID> = value!!.jsonArray.map(::uuid)
    private fun string(value: JsonElement?): String = value!!.jsonPrimitive.content
    private fun optionalInstant(value: JsonElement?): Double? = if (value == null || value is JsonNull) null else instant(value)

    /** Swift's `String(describing:)` of the error case. */
    private fun name(error: ChallengeError): String =
        error.name.lowercase().split('_').mapIndexed { i, part -> if (i == 0) part else part.replaceFirstChar(Char::uppercase) }.joinToString("")

    @Test
    fun ruleCasesMatchTheSwiftResults() {
        var checked = 0
        for (vector in list("cases")) {
            val caseName = string(vector["name"])
            val challenge = Challenge(uuid(vector["owner"]), instant(vector["start"]), Challenge.canonicalZone(string(vector["timeZone"]))!!)
            vector.getValue("steps").jsonArray.forEachIndexed { index, element ->
                val step = element.jsonObject
                val where = "$caseName, step ${index + 1} (${string(step["op"])})"
                checked++
                when (string(step["op"])) {
                    "record" -> {
                        val expectedError = step["error"]?.let(::string)
                        try {
                            val result = challenge.record(Wire.decodeAction(step.getValue("action")), instant(step["on"]),
                                instant(step["at"]), uuid(step["id"]), step["device"]?.let(::string))
                            if (expectedError != null) fail("$where: expected $expectedError")
                            if ("returns" in step) assertNull(where, result) else assertEquals(where, uuid(step["id"]), result)
                        } catch (error: ChallengeException) {
                            assertEquals(where, expectedError, name(error.error))
                        }
                    }
                    "merge" -> {
                        val expectedError = step["error"]?.let(::string)
                        try {
                            challenge.merge(step.getValue("events").jsonArray.map(Wire::decodeActivity))
                            if (expectedError != null) fail("$where: expected $expectedError")
                        } catch (error: ChallengeException) {
                            assertEquals(where, expectedError, name(error.error))
                        }
                    }
                    "summary" -> {
                        val summary = challenge.summary(instant(step["on"]), instant(step["asOf"]))
                        step["water"]?.let { assertEquals(where, it.jsonPrimitive.long, summary.waterMillilitres) }
                        step["waterComplete"]?.let { assertEquals(where, it.jsonPrimitive.boolean, summary.waterComplete) }
                        step["complete"]?.let { assertEquals(where, it.jsonPrimitive.boolean, summary.isComplete) }
                        step["status"]?.let { assertEquals(where, string(it), statusName(summary.status)) }
                        step["diet"]?.let { assertEquals(where, string(it), summary.diet.wire) }
                        step["habits"]?.let { value -> assertEquals(where, value.jsonArray.map(::string).toSet(), summary.completedHabits.map { it.wire }.toSet()) }
                        step["pours"]?.let { assertEquals(where, uuids(it), summary.activePours.map { pour -> pour.id }) }
                        step["intervalDuration"]?.let { assertEquals(where, it.jsonPrimitive.content.toDouble(), summary.intervalDuration, 0.0) }
                        step["intervalStart"]?.let { assertEquals(where, instant(it), summary.intervalStart, 0.0) }
                        step["completedExtras"]?.let { assertEquals(where, uuids(it).toSet(), summary.completedExtras) }
                        step["extrasDone"]?.let { assertEquals(where, it.jsonPrimitive.int, summary.extrasDone) }
                        step["extrasTotal"]?.let { assertEquals(where, it.jsonPrimitive.int, summary.extrasTotal) }
                        step["allExtrasDone"]?.let { assertEquals(where, it.jsonPrimitive.boolean, summary.allExtrasDone) }
                        step["extras"]?.let { value ->
                            val shown = summary.extras.map { extra ->
                                extra.title + (if (extra.id in summary.completedExtras) " ✓" else "") + (if (summary.isLate(extra)) " late" else "")
                            }
                            assertEquals(where, value.jsonArray.map(::string), shown)
                        }
                    }
                    "streaks" -> {
                        val streaks = challenge.streaks(instant(step["asOf"]))
                        assertEquals(where, step.getValue("current").jsonPrimitive.int, streaks.current)
                        step["best"]?.let { assertEquals(where, it.jsonPrimitive.int, streaks.best) }
                        step["milestones"]?.let { value -> assertEquals(where, value.jsonArray.map(::instant), streaks.milestones) }
                    }
                    "history" -> {
                        val history = challenge.history(instant(step["on"]))
                        assertEquals(where, uuids(step["ids"]), history.map { it.id })
                        (step["undone"] as? JsonObject)?.forEach { (undo, pour) ->
                            assertEquals(where, uuid(pour), history.first { it.id == UUID.fromString(undo) }.undonePourID)
                        }
                    }
                    "activities" -> assertEquals(where, uuids(step["ids"]), challenge.allActivities.map { it.id })
                    "activityDays" -> assertEquals(where, step.getValue("days").jsonArray.map(::instant), challenge.allActivities.map { it.day })
                    "startDate" -> assertEquals(where, instant(step["equals"]), challenge.startDate, 0.0)
                    "allExtras" -> {
                        val expected = step.getValue("extras").jsonArray.map { it.jsonObject }
                        assertEquals(where, expected.size, challenge.allExtras.size)
                        challenge.allExtras.zip(expected).forEach { (extra, want) ->
                            assertEquals(where, uuid(want["id"]), extra.id)
                            assertEquals(where, string(want["title"]), extra.title)
                            assertEquals(where, instant(want["firstDay"]), extra.firstDay, 0.0)
                            assertEquals(where, optionalInstant(want["completedOn"]), extra.completedOn)
                            assertEquals(where, optionalInstant(want["archivedFrom"]), extra.archivedFrom)
                        }
                    }
                    "shownExtras" -> assertEquals(where, uuids(step["ids"]), challenge.extras(instant(step["asOf"])).map { it.id })
                    "openExtras" -> assertEquals(where, uuids(step["ids"]), challenge.openExtras(instant(step["asOf"])).map { it.id })
                    "shownExtrasCount" -> assertEquals(where, step.getValue("count").jsonPrimitive.int, challenge.extras(instant(step["asOf"])).size)
                    "openExtrasCount" -> assertEquals(where, step.getValue("count").jsonPrimitive.int, challenge.openExtras(instant(step["asOf"])).size)
                    else -> fail("Unknown op in $where")
                }
            }
        }
        check(checked > 1_000) { "Only $checked steps ran" }
    }

    private fun statusName(status: DayStatus) = when (status) {
        DayStatus.OUTSIDE_CHALLENGE -> "outsideChallenge"
        DayStatus.FUTURE -> "future"
        DayStatus.IN_PROGRESS -> "inProgress"
        DayStatus.MISSED -> "missed"
        DayStatus.COMPLETE -> "complete"
    }

    private fun encode(kind: String, value: JsonElement): JsonElement = when (kind) {
        "action" -> Wire.encode(Wire.decodeAction(value))
        "activity" -> Wire.encode(Wire.decodeActivity(value))
        "record" -> Wire.encode(Wire.decodeRecord(value))
        "event" -> Wire.encode(Wire.decodeEvent(value))
        else -> error(kind)
    }

    @Test
    fun wireFormatIsByteForByteTheSwiftEncoding() {
        for (entry in list("encoding") + list("spellings")) {
            val encoded = encode(string(entry["kind"]), entry.getValue("value"))
            assertEquals(entry["value"].toString(), string(entry["sorted"]), Wire.text(encoded, sortKeys = true))
        }
        // Unsorted, the keys follow Swift's CodingKeys order.
        val activity = Wire.decodeActivity(list("encoding").first { string(it["kind"]) == "activity" && it.getValue("value").jsonObject.containsKey("undonePourID") }.getValue("value"))
        assertEquals(
            "{\"id\":\"AAAAAAAA-0000-4000-8000-000000000001\",\"day\":781484400,\"recordedAt\":781527600.25," +
                "\"action\":{\"undoLatestPour\":{}},\"undonePourID\":\"BBBBBBBB-0000-4000-8000-000000000001\"," +
                "\"deviceID\":\"legacy-00000000000000000003\"}",
            Wire.text(Wire.encode(activity)),
        )
        for (entry in list("rejected")) {
            try {
                encode(string(entry["kind"]), entry.getValue("value"))
                fail("Accepted ${entry["value"]}")
            } catch (_: WireException) {
            }
        }
        for (entry in list("records")) {
            val record = Wire.decodeRecord(entry.getValue("value"))
            assertEquals(string(entry["timeZone"]), record.timeZone)
            assertEquals(entry["value"].toString(), entry.getValue("valid").jsonPrimitive.boolean, record.emptyChallenge() != null)
        }
    }

    @Test
    fun smallRulesMatchTheSwiftResults() {
        for (entry in list("zones")) {
            assertEquals(string(entry["identifier"]), entry.getValue("canonical").jsonPrimitive.boolean,
                Challenge.canonicalZone(string(entry["identifier"])) != null)
        }
        for (entry in list("titles")) {
            val expected = (entry["title"] as? JsonPrimitive)?.takeIf { it.isString }?.content
            assertEquals(string(entry["raw"]), expected, Challenge.extraTitle(string(entry["raw"])))
        }
        for (entry in list("clockWarnings")) {
            val at = instant(entry["recordedAt"])
            val event = ChallengeEvent(UUID.randomUUID(), UUID.randomUUID(),
                Activity(UUID.randomUUID(), at, at, Action.Pour(450), null, "fixture"), string(entry["receivedAt"]))
            assertEquals(string(entry["receivedAt"]), entry.getValue("warning").jsonPrimitive.boolean, event.hasClockWarning)
        }
    }

}

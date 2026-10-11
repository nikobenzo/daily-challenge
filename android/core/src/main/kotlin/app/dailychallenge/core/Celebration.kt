package app.dailychallenge.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.util.UUID

enum class CompletionCelebration { DAILY, MILESTONE, EXTRAS }

data class CelebrationEvent(val kind: CompletionCelebration, val started: Double, val id: UUID = UUID.randomUUID()) {
    val duration: Double get() = if (kind == CompletionCelebration.MILESTONE) 3.0 else 1.8
}

/**
 * Separate from synced history (Swift `CelebrationLedger`). Observed completions are consumed
 * even on open or sync, so undo and re-complete never replay an achievement. A failed or
 * corrupt ledger suppresses effects rather than risking a replay.
 */
class CelebrationLedger(val file: File) {
    fun observe(challenge: Challenge, challengeID: UUID, now: Double, localCompletionDay: Double? = null,
                localExtrasDay: Double? = null): CompletionCelebration? = try {
        val seen: MutableSet<String> = if (file.exists()) {
            Wire.json.parseToJsonElement(file.readText()).jsonArray.mapTo(HashSet()) { it.jsonPrimitive.content }
        } else HashSet()
        val today = challenge.day(now)
        fun key(kind: String, day: Double) = "${Challenge.uuidString(challengeID)}/$kind/${ChallengeTime.toUnix(day)}"
        val days = challenge.allActivities.map { it.day }.toSet()
        val completeDays = days.filter { challenge.summary(it, now).isComplete }.toSet()
        val milestones = challenge.streaks(now).milestones
        val eligible = localCompletionDay == today && today in completeDays
        val daily = eligible && key("day", today) !in seen
        val milestone = eligible && today in milestones && key("milestone", today) !in seen
        val extrasDays = days.filter { challenge.summary(it, now).allExtrasDone }.toSet()
        val extras = localExtrasDay == today && today in extrasDays && key("extras", today) !in seen
        val previous = seen.toSet()
        completeDays.forEach { seen.add(key("day", it)) }
        milestones.forEach { seen.add(key("milestone", it)) }
        extrasDays.forEach { seen.add(key("extras", it)) }
        if (seen != previous) {
            file.parentFile?.mkdirs()
            val temporary = File(file.parentFile, "${file.name}.tmp")
            temporary.writeText(Wire.text(JsonArray(seen.sorted().map(::JsonPrimitive))))
            if (!temporary.renameTo(file)) throw java.io.IOException("Could not save the celebration ledger")
        }
        when {
            milestone -> CompletionCelebration.MILESTONE
            daily -> CompletionCelebration.DAILY
            extras -> CompletionCelebration.EXTRAS
            else -> null
        }
    } catch (_: Exception) {
        null
    }

    companion object {
        fun fileName(ownerID: UUID) = "celebrations-${Challenge.uuidString(ownerID)}.json"
    }
}

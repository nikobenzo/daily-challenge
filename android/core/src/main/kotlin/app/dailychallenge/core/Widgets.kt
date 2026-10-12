package app.dailychallenge.core

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.ZoneId
import java.util.UUID

/**
 * The only identity a widget control carries: opaque and credential-free. A tap is refused
 * once the app publishes another generation (sign-out, account switch or deletion) or the
 * account's challenge is not this one.
 */
data class WidgetBinding(val generation: UUID, val challengeID: UUID)

/** What the app publishes for its widgets: the signed-in account and an opaque generation. Never a token or an email. */
data class WidgetAccount(val ownerID: UUID, val generation: UUID)

/**
 * The widget account file beside the history. The app publishes it on every session change;
 * widgets only read it, and never choose an account by listing files.
 */
class WidgetAccountStore(directory: File) {
    val file = File(directory, FILE_NAME)
    private val lock = StoreLock(directory)

    /** Null when signed out, never published, or unreadable: widgets then show signed out. */
    fun read(): WidgetAccount? {
        if (!file.exists()) return null
        return try {
            val root = Wire.json.parseToJsonElement(file.readText()) as? JsonObject ?: return null
            if ((root["version"] as? JsonPrimitive)?.content != "1") return null
            WidgetAccount(Wire.uuidOf(root["ownerID"], "ownerID"), Wire.uuidOf(root["generation"], "generation"))
        } catch (_: Exception) {
            null
        }
    }

    /**
     * The signed-in account, or null after sign-out or deletion. The same account keeps its
     * generation across launches; any change issues a new one, so earlier widget taps are refused.
     */
    fun publish(ownerID: UUID?): WidgetAccount? = lock.withLock {
        val current = read()
        when {
            ownerID == null -> {
                if (file.exists() && !file.delete()) throw java.io.IOException("Could not clear the widget account")
                null
            }
            current?.ownerID == ownerID -> current
            else -> WidgetAccount(ownerID, UUID.randomUUID()).also(::write)
        }
    }

    private fun write(account: WidgetAccount) {
        file.parentFile?.mkdirs()
        val temporary = File(file.parentFile, "${file.name}.${UUID.randomUUID()}.tmp")
        try {
            temporary.writeText(Wire.text(JsonObject(linkedMapOf(
                "generation" to Wire.uuid(account.generation),
                "ownerID" to Wire.uuid(account.ownerID),
                "version" to JsonPrimitive(1),
            ))))
            Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally {
            temporary.delete()
        }
    }

    companion object {
        const val FILE_NAME = "widget-account.json"
    }
}

/** Everything a widget draws, derived at one instant in the challenge's zone. */
sealed interface WidgetState {
    /** The calm line shown instead of data: no cached titles or totals from another account. */
    val message: String

    data object SignedOut : WidgetState { override val message = "Open Daily Challenge to sign in" }
    data object NoChallenge : WidgetState { override val message = "Open Daily Challenge to set up" }
    data object Unavailable : WidgetState { override val message = "Open Daily Challenge" }

    data class Ready(
        val binding: WidgetBinding,
        val zone: ZoneId,
        val summary: DailySummary,
        /** Null before the start date in the challenge's zone. */
        val dayNumber: Int?,
        val streak: Int,
        /** "12 Oct · Jersey": the challenge's own date, so a different zone stays intelligible. */
        val dateLabel: String,
        /** The next day boundary in the challenge's zone, when the widgets need redrawing. */
        val nextMidnight: Double,
    ) : WidgetState {
        override val message = ""
    }

    companion object {
        /** Reads the published account and its history without the lock: commits replace files atomically. */
        fun load(directory: File, now: Double = ChallengeTime.now(), locale: java.util.Locale = java.util.Locale.getDefault()): WidgetState {
            val account = WidgetAccountStore(directory).read() ?: return SignedOut
            return try {
                val store = ChallengeStore(account.ownerID, directory)
                derive(store.challenge ?: return NoChallenge, store.record ?: return NoChallenge, account, now, locale)
            } catch (_: Exception) {
                Unavailable
            }
        }

        fun derive(challenge: Challenge, record: ChallengeRecord, account: WidgetAccount, now: Double,
                   locale: java.util.Locale = java.util.Locale.getDefault()): Ready {
            val dates = ChallengeDates(challenge.zone, locale)
            val today = dates.calendar.startOfDay(now)
            val number = dates.calendar.daysBetween(challenge.startDate, today).toInt() + 1
            return Ready(
                binding = WidgetBinding(account.generation, record.id),
                zone = challenge.zone,
                summary = challenge.summary(now, now),
                dayNumber = number.takeIf { it > 0 },
                streak = challenge.streaks(now).current,
                dateLabel = dates.label(now, "d MMM") + " · " + ChallengeDates.city(challenge.zone),
                nextMidnight = dates.calendar.interval(now).second,
            )
        }
    }
}

/** What a widget tap asks for. The stored state, re-read inside the lock, decides the actual event. */
sealed interface WidgetTap {
    data object Pour : WidgetTap
    data object UndoPour : WidgetTap
    data class ToggleHabit(val habit: Habit) : WidgetTap
    data object ToggleDiet : WidgetTap
    data class ToggleExtra(val id: UUID) : WidgetTap

    val kind: String
        get() = when (this) {
            Pour -> "pour"; UndoPour -> "undoPour"; is ToggleHabit -> "habit"; ToggleDiet -> "diet"; is ToggleExtra -> "extra"
        }

    val target: String
        get() = when (this) {
            is ToggleHabit -> habit.wire
            is ToggleExtra -> Challenge.uuidString(id)
            else -> ""
        }

    companion object {
        /** Tap parameters arrive as strings: only supported habits and extra IDs parse; no owner, date, amount or path. */
        fun parse(kind: String?, target: String?): WidgetTap? = when (kind) {
            "pour" -> Pour
            "undoPour" -> UndoPour
            "diet" -> ToggleDiet
            "habit" -> target?.let(Habit::fromWire)?.let(::ToggleHabit)
            "extra" -> target?.let { runCatching { UUID.fromString(it) }.getOrNull() }?.let(::ToggleExtra)
            else -> null
        }
    }
}

sealed interface WidgetOutcome {
    /** Durably saved in the history and its pending queue; the app's sync uploads it. */
    data class Recorded(val eventID: UUID) : WidgetOutcome
    /** Minus with no pour today: no event and no error. */
    data object Unchanged : WidgetOutcome
    /** A diet already marked missed is left alone; the widget opens the app instead. */
    data object OpenApp : WidgetOutcome
    /** Signed out, another account or challenge, an extra no longer shown today, or a day outside the challenge. */
    data object Refused : WidgetOutcome
}

/**
 * Widget taps without the app's screens or session: each is an existing [Action] recorded
 * through [ChallengeStore.record] inside the [StoreLock] transaction the app's own edits and
 * sync merge use, so a tap and an in-app edit never lose or duplicate each other. The day
 * comes from the tap time in the challenge's zone, never from what the widget last drew, and
 * so does + : it pours that day's glass size from the stored targets.
 * No network: the app's sync uploads the pending queue later.
 */
class WidgetActions(private val directory: File, private val clock: () -> Double = ChallengeTime::now) {
    private val lock = StoreLock(directory)

    fun perform(tap: WidgetTap, binding: WidgetBinding): WidgetOutcome = lock.withLock {
        val account = WidgetAccountStore(directory).read()
        if (account == null || account.generation != binding.generation) return@withLock WidgetOutcome.Refused
        val store = ChallengeStore(account.ownerID, directory)
        val challenge = store.challenge ?: return@withLock WidgetOutcome.Refused
        if (store.record?.id != binding.challengeID) return@withLock WidgetOutcome.Refused
        // Captured once, inside the lock: the tap's own day.
        val now = clock()
        val today = challenge.summary(now, now)
        if (today.status == DayStatus.OUTSIDE_CHALLENGE || today.status == DayStatus.FUTURE) return@withLock WidgetOutcome.Refused
        val action = when (tap) {
            WidgetTap.Pour -> Action.Pour(today.targets.water.glass)
            WidgetTap.UndoPour -> if (today.activePours.isEmpty()) return@withLock WidgetOutcome.Unchanged else Action.UndoLatestPour
            is WidgetTap.ToggleHabit -> Action.SetHabit(tap.habit, tap.habit !in today.completedHabits)
            WidgetTap.ToggleDiet -> when (today.diet) {
                DietState.MISSED -> return@withLock WidgetOutcome.OpenApp
                DietState.PENDING -> Action.SetDiet(DietState.CLEAN)
                DietState.CLEAN -> Action.SetDiet(DietState.PENDING)
            }
            is WidgetTap.ToggleExtra -> {
                if (today.extras.none { it.id == tap.id }) return@withLock WidgetOutcome.Refused
                Action.SetExtra(tap.id, tap.id !in today.completedExtras)
            }
        }
        store.record(action, now, now)?.let { WidgetOutcome.Recorded(it) } ?: WidgetOutcome.Unchanged
    }
}

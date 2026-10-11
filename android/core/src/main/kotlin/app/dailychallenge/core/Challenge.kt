package app.dailychallenge.core

import java.text.BreakIterator
import java.time.ZoneId
import java.util.UUID

/** Swift `ChallengeError`: the same cases and words, so every device explains a refusal alike. */
enum class ChallengeError(val message: String) {
    INVALID_WATER_AMOUNT("Water amounts must be positive whole millilitres within the supported total."),
    DATE_OUTSIDE_CHALLENGE("Only days from the challenge start through today can be edited."),
    CONFLICTING_ACTIVITY("An activity ID was reused with different content. Nothing was changed."),
    INVALID_EXTRA_TITLE("An extra's name must be 1 to 40 characters on one line."),
    TOO_MANY_EXTRAS("You can have up to ${Challenge.MAXIMUM_ACTIVE_EXTRAS} extras. Archive one to add another."),
    UNKNOWN_EXTRA("That extra doesn't exist. Nothing was changed."),
    ARCHIVED_EXTRA("That extra is archived, so it can't be changed for this day."),
}

class ChallengeException(val error: ChallengeError) : Exception(error.message)

enum class Habit(val wire: String) {
    WORKOUT("workout"), WALK("walk"), BIBLE_READING("bibleReading");

    companion object {
        fun fromWire(value: String): Habit? = entries.firstOrNull { it.wire == value }
    }
}

enum class DietState(val wire: String) {
    PENDING("pending"), CLEAN("clean"), MISSED("missed");

    companion object {
        fun fromWire(value: String): DietState? = entries.firstOrNull { it.wire == value }
    }
}

/**
 * One event's change. The JSON names (see [Wire]) are the wire format shared with the
 * server and every client, so they never change. Extras never count toward a complete day.
 */
sealed interface Action {
    /** Millilitres; 64-bit like Swift's `Int`, so totals overflow at the same point. */
    data class Pour(val millilitres: Long) : Action
    data object UndoLatestPour : Action
    data class SetHabit(val habit: Habit, val completed: Boolean) : Action
    data class SetDiet(val state: DietState) : Action
    /** Adds an extra, or renames it: the last definition in event order wins. */
    data class DefineExtra(val id: UUID, val title: String) : Action
    /** Hides an extra from its archive day on, permanently; earlier days keep their ticks. */
    data class ArchiveExtra(val id: UUID) : Action
    /** Ticks or unticks an extra for the event's day. The earliest ticked day completes it. */
    data class SetExtra(val id: UUID, val completed: Boolean) : Action
}

/** An immutable event. `day` and `recordedAt` are reference seconds ([ChallengeTime]). */
data class Activity(
    val id: UUID,
    val day: Double,
    val recordedAt: Double,
    val action: Action,
    val undonePourID: UUID?,
    val deviceID: String? = null,
)

data class WaterPour(val id: UUID, val millilitres: Long)

enum class DayStatus { OUTSIDE_CHALLENGE, FUTURE, IN_PROGRESS, MISSED, COMPLETE }

/**
 * A personal to-do beside the five requirements that carries over, day by day, until it is
 * done or archived. Never part of `isComplete`. All three days derive from the extras events.
 */
data class Extra(
    val id: UUID,
    val title: String,
    /** The first challenge day it is shown on; later days mark it late. */
    val firstDay: Double,
    /** The earliest day it is ticked on, before any archive, or null while it is open. */
    val completedOn: Double?,
    /** The first challenge day it is hidden from, or null while it is active. */
    val archivedFrom: Double?,
) {
    val isArchived: Boolean get() = archivedFrom != null

    fun isShown(day: Double): Boolean =
        firstDay <= day && (completedOn?.let { day <= it } ?: true) && (archivedFrom?.let { day < it } ?: true)
}

data class DailySummary(
    val intervalStart: Double,
    val intervalEnd: Double,
    val activePours: List<WaterPour>,
    val completedHabits: Set<Habit>,
    val diet: DietState,
    val status: DayStatus,
    /** The extras shown for this day, in creation order, and which of them are ticked. */
    val extras: List<Extra>,
    val completedExtras: Set<UUID>,
) {
    val waterMillilitres: Long get() = activePours.sumOf { it.millilitres }
    val waterComplete: Boolean get() = waterMillilitres >= 4_000
    /** The five requirements only. Extras never change it. */
    val isComplete: Boolean get() = status == DayStatus.COMPLETE
    val extrasDone: Int get() = completedExtras.size
    val extrasTotal: Int get() = extras.size
    val allExtrasDone: Boolean get() = extrasTotal > 0 && extrasDone == extrasTotal
    val intervalDuration: Double get() = intervalEnd - intervalStart
    /** Carried over: shown on a day after the first day it appeared, ticked or not. */
    fun isLate(extra: Extra): Boolean = extra.firstDay < intervalStart
}

data class StreakSummary(val current: Int, val best: Int, val milestones: List<Double>)

/**
 * The rules, ported from `Sources/ChallengeCore/Challenge.swift`: days in the challenge's
 * zone, requirements, undo, corrections, merge, streaks and the extras day rules. Mutating
 * calls replace the activity list, so [copy] is cheap and copies never share state.
 */
class Challenge(val ownerID: UUID, startDate: Double, val zone: ZoneId) {
    val calendar = ChallengeCalendar(zone)
    val startDate: Double = calendar.startOfDay(startDate)
    private var activities: List<Activity> = emptyList()

    val allActivities: List<Activity> get() = activities

    fun copy(): Challenge = Challenge(ownerID, startDate, zone).also { it.activities = activities }

    fun day(instant: Double): Double = calendar.startOfDay(instant)

    /** Records a local edit. Returns the event ID, or null when nothing needed recording. */
    fun record(action: Action, on: Double, at: Double, id: UUID = UUID.randomUUID(), deviceID: String? = null): UUID? {
        activities.firstOrNull { it.id == id }?.let { existing ->
            if (existing.day != day(on) || existing.recordedAt != at || existing.action != action) {
                throw ChallengeException(ChallengeError.CONFLICTING_ACTIVITY)
            }
            return id
        }
        if (day(on) < startDate || day(on) > day(at)) throw ChallengeException(ChallengeError.DATE_OUTSIDE_CHALLENGE)
        val target: UUID? = when (action) {
            is Action.Pour -> {
                if (action.millilitres <= 0 || addOverflows(summary(on, at).waterMillilitres, action.millilitres)) {
                    throw ChallengeException(ChallengeError.INVALID_WATER_AMOUNT)
                }
                null
            }
            is Action.SetHabit, is Action.SetDiet -> null
            is Action.DefineExtra -> {
                if (extraTitle(action.title) != action.title) throw ChallengeException(ChallengeError.INVALID_EXTRA_TITLE)
                val existing = allExtras.firstOrNull { it.id == action.id }
                if (existing != null) {
                    if (existing.isArchived) throw ChallengeException(ChallengeError.ARCHIVED_EXTRA)
                } else if (openExtras(at).size >= MAXIMUM_ACTIVE_EXTRAS) {
                    throw ChallengeException(ChallengeError.TOO_MANY_EXTRAS)
                }
                null
            }
            is Action.ArchiveExtra -> {
                val existing = allExtras.firstOrNull { it.id == action.id }
                    ?: throw ChallengeException(ChallengeError.UNKNOWN_EXTRA)
                if (existing.isArchived) return null
                null
            }
            is Action.SetExtra -> {
                val existing = allExtras.firstOrNull { it.id == action.id }
                    ?: throw ChallengeException(ChallengeError.UNKNOWN_EXTRA)
                if (!(existing.archivedFrom?.let { it > day(on) } ?: true)) {
                    throw ChallengeException(ChallengeError.ARCHIVED_EXTRA)
                }
                null
            }
            Action.UndoLatestPour -> summary(on, at).activePours.lastOrNull()?.id ?: return null
        }
        val record = Activity(id, day(on), at, action, target, deviceID)
        if (deviceID != null) merge(listOf(record)) else activities = activities + record
        return record.id
    }

    /**
     * Union immutable events, then derive state. Undo targets are never replayed as
     * commands: two devices undoing one pour must not remove two different pours.
     */
    fun merge(incoming: List<Activity>) {
        val known = LinkedHashMap<UUID, Activity>()
        activities.forEach { known[it.id] = it }
        for (event in incoming) {
            val existing = known[event.id]
            if (existing != null && existing != event) throw ChallengeException(ChallengeError.CONFLICTING_ACTIVITY)
            known[event.id] = event
        }
        val totals = HashMap<Double, Long>()
        val undone = known.values.mapNotNullTo(HashSet()) { it.undonePourID }
        // Order-independent on purpose: a device may tick an extra before it hears of
        // another device's archive, or with a clock behind the definition's. Only an
        // extra never defined anywhere in the union is invalid.
        val definedExtras = known.values.mapNotNullTo(HashSet()) { (it.action as? Action.DefineExtra)?.id }
        for (event in known.values) {
            if (!event.day.isFinite() || !event.recordedAt.isFinite() || day(event.day) != event.day ||
                event.day < startDate || event.day > day(event.recordedAt)
            ) throw ChallengeException(ChallengeError.DATE_OUTSIDE_CHALLENGE)
            when (val action = event.action) {
                is Action.Pour -> {
                    if (action.millilitres <= 0 || event.undonePourID != null) {
                        throw ChallengeException(ChallengeError.INVALID_WATER_AMOUNT)
                    }
                    if (event.id !in undone) {
                        val current = totals[event.day] ?: 0L
                        if (addOverflows(current, action.millilitres)) throw ChallengeException(ChallengeError.INVALID_WATER_AMOUNT)
                        totals[event.day] = current + action.millilitres
                    }
                }
                Action.UndoLatestPour -> {
                    val target = event.undonePourID?.let { known[it] }
                    if (target == null || target.action !is Action.Pour || target.day != event.day) {
                        throw ChallengeException(ChallengeError.CONFLICTING_ACTIVITY)
                    }
                }
                is Action.SetHabit, is Action.SetDiet -> {
                    if (event.undonePourID != null) throw ChallengeException(ChallengeError.CONFLICTING_ACTIVITY)
                }
                is Action.DefineExtra -> {
                    if (event.undonePourID != null) throw ChallengeException(ChallengeError.CONFLICTING_ACTIVITY)
                    if (extraTitle(action.title) != action.title) throw ChallengeException(ChallengeError.INVALID_EXTRA_TITLE)
                }
                is Action.ArchiveExtra, is Action.SetExtra -> {
                    if (event.undonePourID != null) throw ChallengeException(ChallengeError.CONFLICTING_ACTIVITY)
                    val extraID = if (action is Action.ArchiveExtra) action.id else (action as Action.SetExtra).id
                    if (extraID !in definedExtras) throw ChallengeException(ChallengeError.UNKNOWN_EXTRA)
                }
            }
        }
        activities = known.values.sortedWith(eventOrder)
    }

    fun history(on: Double): List<Activity> {
        val selected = day(on)
        return activities.filter { it.day == selected }
    }

    fun summary(on: Double, asOf: Double): DailySummary {
        val records = history(on)
        val undone = records.mapNotNullTo(HashSet()) { it.undonePourID }
        val pours = records.mapNotNull { record ->
            val action = record.action
            if (action is Action.Pour && record.id !in undone) WaterPour(record.id, action.millilitres) else null
        }
        val completed = LinkedHashSet<Habit>()
        var diet = DietState.PENDING
        val ticked = HashSet<UUID>()
        for (record in records) {
            when (val action = record.action) {
                is Action.SetHabit -> if (action.completed) completed.add(action.habit) else completed.remove(action.habit)
                is Action.SetDiet -> diet = action.state
                is Action.SetExtra -> if (action.completed) ticked.add(action.id) else ticked.remove(action.id)
                else -> Unit
            }
        }
        val selected = day(on)
        val shown = extras(selected)
        val today = day(asOf)
        val allMet = pours.sumOf { it.millilitres } >= 4_000 && completed.size == Habit.entries.size && diet == DietState.CLEAN
        val status = when {
            selected < startDate -> DayStatus.OUTSIDE_CHALLENGE
            selected > today -> DayStatus.FUTURE
            allMet -> DayStatus.COMPLETE
            selected < today -> DayStatus.MISSED
            else -> DayStatus.IN_PROGRESS
        }
        val (start, end) = calendar.interval(selected)
        val shownIDs = shown.mapTo(HashSet()) { it.id }
        return DailySummary(start, end, pours, completed, diet, status, shown, ticked.filterTo(HashSet()) { it in shownIDs })
    }

    /**
     * Every extra ever defined, archived ones included, in creation order. Order-independent
     * like [merge]: the earliest definition day, the earliest archive day and each day's last
     * tick in event order. `firstDay` is the earliest definition day, or the completion day
     * when that is earlier.
     */
    val allExtras: List<Extra>
        get() {
            val order = ArrayList<UUID>()
            val titles = HashMap<UUID, String>()
            val defined = HashMap<UUID, Double>()
            val archived = HashMap<UUID, Double>()
            val ticks = HashMap<UUID, HashMap<Double, Boolean>>()
            for (activity in activities) {
                when (val action = activity.action) {
                    is Action.DefineExtra -> {
                        if (titles[action.id] == null) order.add(action.id)
                        titles[action.id] = action.title
                        defined[action.id] = minOf(defined[action.id] ?: activity.day, activity.day)
                    }
                    is Action.ArchiveExtra -> archived[action.id] = minOf(archived[action.id] ?: activity.day, activity.day)
                    is Action.SetExtra -> ticks.getOrPut(action.id) { HashMap() }[activity.day] = action.completed
                    else -> Unit
                }
            }
            return order.mapNotNull { id ->
                val title = titles[id] ?: return@mapNotNull null
                val definedOn = defined[id] ?: return@mapNotNull null
                // A tick from its archive day on is kept as history but never completes it.
                val completedOn = ticks[id]?.filter { (day, value) -> value && (archived[id]?.let { day < it } ?: true) }
                    ?.keys?.minOrNull()
                Extra(id, title, minOf(definedOn, completedOn ?: definedOn), completedOn, archived[id])
            }
        }

    /** The extras shown for the day of `date`, in creation order. */
    fun extras(asOf: Double): List<Extra> {
        val selected = day(asOf)
        return allExtras.filter { it.isShown(selected) }
    }

    /** Neither archived nor completed on or before that day: what the cap counts. */
    fun openExtras(asOf: Double): List<Extra> {
        val selected = day(asOf)
        return allExtras.filter { !it.isArchived && (it.completedOn?.let { done -> done > selected } ?: true) }
    }

    fun streaks(asOf: Double): StreakSummary {
        val today = day(asOf)
        var date = calendar.localDate(startDate)
        var run = 0
        var best = 0
        var current = 0
        val milestones = ArrayList<Double>()
        while (calendar.startOf(date) <= today) {
            val day = calendar.startOf(date)
            if (summary(day, asOf).isComplete) {
                run += 1
                best = maxOf(best, run)
                current = run
                if (run == 75) milestones.add(day)
            } else if (day < today) {
                run = 0
                current = 0
            }
            // Pending today preserves the sequence ending yesterday.
            date = date.plusDays(1)
        }
        return StreakSummary(current, best, milestones)
    }

    companion object {
        const val MAXIMUM_ACTIVE_EXTRAS = 10
        const val MAXIMUM_EXTRA_TITLE_LENGTH = 40
        /** Challenges and data from before per-challenge timezones were all Jersey days. */
        const val LEGACY_TIME_ZONE_ID = "Europe/Jersey"
        val legacyZone: ZoneId get() = ZoneId.of(LEGACY_TIME_ZONE_ID)

        /** Distributed ordering: client timestamp, then device ID, then event ID. */
        val eventOrder: Comparator<Activity> = Comparator { a, b ->
            when {
                a.recordedAt != b.recordedAt -> a.recordedAt.compareTo(b.recordedAt)
                a.deviceID != b.deviceID -> (a.deviceID ?: "").compareTo(b.deviceID ?: "")
                else -> uuidString(a.id).compareTo(uuidString(b.id))
            }
        }

        /** Swift's `uuidString`: upper case. */
        fun uuidString(id: UUID): String = id.toString().uppercase()

        /**
         * A zone is accepted only in a spelling Apple's Foundation keeps as is (it turns
         * "UTC" into "GMT"), so comparing identifiers compares zones on every device.
         */
        fun canonicalZone(identifier: String): ZoneId? {
            if (identifier in nonCanonicalZones || !identifier.matches(zonePattern)) return null
            return try {
                ZoneId.of(identifier).takeIf { it.id == identifier }
            } catch (_: Exception) {
                null
            }
        }

        private val nonCanonicalZones = setOf("UTC", "UCT", "Z", "Universal", "Zulu", "GMT0", "GMT+0", "GMT-0", "Greenwich")
        private val zonePattern = Regex("[A-Za-z][A-Za-z0-9_+\\-]*(/[A-Za-z0-9_+\\-]+)*")

        /** The stored form of an extra's name: trimmed, 1 to 40 characters, one line. */
        fun extraTitle(raw: String): String? {
            val title = trimWhitespaceAndNewlines(raw)
            val length = graphemeCount(title)
            if (length < 1 || length > MAXIMUM_EXTRA_TITLE_LENGTH) return null
            var index = 0
            while (index < title.length) {
                val scalar = title.codePointAt(index)
                if (isControl(scalar) || isNewline(scalar)) return null
                index += Character.charCount(scalar)
            }
            return title
        }

        /** Swift `CharacterSet.whitespacesAndNewlines`: Z*, U+0009 to U+000D and U+0085. */
        private fun isWhitespaceOrNewline(c: Int): Boolean {
            val type = Character.getType(c)
            return type == Character.SPACE_SEPARATOR.toInt() || type == Character.LINE_SEPARATOR.toInt() ||
                type == Character.PARAGRAPH_SEPARATOR.toInt() || c in 0x09..0x0D || c == 0x85
        }

        /** Swift `CharacterSet.controlCharacters`: general categories Cc and Cf. */
        private fun isControl(c: Int): Boolean {
            val type = Character.getType(c)
            return type == Character.CONTROL.toInt() || type == Character.FORMAT.toInt()
        }

        /** Swift `CharacterSet.newlines`. */
        private fun isNewline(c: Int): Boolean = c in 0x0A..0x0D || c == 0x85 || c == 0x2028 || c == 0x2029

        private fun trimWhitespaceAndNewlines(value: String): String {
            var start = 0
            var end = value.length
            while (start < end && isWhitespaceOrNewline(value.codePointAt(start))) start += Character.charCount(value.codePointAt(start))
            while (end > start && isWhitespaceOrNewline(value.codePointBefore(end))) end -= Character.charCount(value.codePointBefore(end))
            return value.substring(start, end)
        }

        /** Swift's `String.count`: extended grapheme clusters, not UTF-16 units. */
        fun graphemeCount(value: String): Int {
            if (value.isEmpty()) return 0
            val iterator = BreakIterator.getCharacterInstance()
            iterator.setText(value)
            var count = 0
            while (iterator.next() != BreakIterator.DONE) count++
            return count
        }

        private fun addOverflows(a: Long, b: Long): Boolean {
            val sum = a + b
            return ((a xor sum) and (b xor sum)) < 0
        }
    }
}

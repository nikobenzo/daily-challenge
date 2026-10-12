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
    INVALID_TARGET("A goal needs a name of 1 to 20 characters on one line, and amounts within their limits. Nothing was changed."),
    INVALID_SCHEDULE("An extra repeats on chosen weekdays or every 1 to 30 days. Nothing was changed."),
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
 * The four labelled slots beside water (Swift `Challenge.TargetSlot`). A key only identifies a
 * ring and its `setHabit` or `setDiet` events, so `walk` may be labelled Yoga. Never rename them.
 */
enum class TargetSlot(val wire: String) {
    WORKOUT("workout"), WALK("walk"), DIET("diet"), BIBLE_READING("bibleReading");

    companion object {
        fun fromWire(value: String): TargetSlot? = entries.firstOrNull { it.wire == value }
    }
}

/** The units of an activity's optional amount, each with the amounts it allows. */
enum class TargetUnit(val wire: String, val amounts: LongRange) {
    MINUTES("minutes", 5L..300L), PAGES("pages", 1L..500L), CHAPTERS("chapters", 1L..50L),
    KILOMETRES("kilometres", 1L..100L), MILES("miles", 1L..60L), STEPS("steps", 1_000L..50_000L);

    companion object {
        fun fromWire(value: String): TargetUnit? = entries.firstOrNull { it.wire == value }
    }
}

/**
 * What a slot is called and, optionally, how much. Display only: the slot is still completed
 * by its tick (or, for diet, by a clean day). An [icon] id this version does not know, or
 * none, shows the slot's default icon.
 */
data class Target(val name: String, val amount: Long? = null, val unit: TargetUnit? = null, val icon: String? = null) {
    /**
     * The rules every client and the server apply: a valid name, an amount and unit together
     * or neither (diet takes none), the amount in its unit's range, and an icon id of 1 to 16
     * lower-case letters.
     */
    fun isValid(slot: TargetSlot): Boolean {
        if (Challenge.targetName(name) != name || (icon != null && !Challenge.isIconID(icon))) return false
        return when {
            amount == null && unit == null -> true
            amount != null && unit != null -> slot != TargetSlot.DIET && amount in unit.amounts
            else -> false
        }
    }
}

/** The daily water goal and the glass the + button pours, in millilitres. */
data class WaterTarget(val goal: Long, val glass: Long) {
    val isValid: Boolean get() = goal in GOALS && glass in GLASSES && glass <= goal

    companion object {
        val GOALS = 1_000L..5_000L
        val GLASSES = 50L..1_000L
    }
}

/** The targets in force on one challenge day. */
data class Targets(
    val water: WaterTarget,
    val workout: Target,
    val walk: Target,
    val diet: Target,
    val bibleReading: Target,
) {
    operator fun get(slot: TargetSlot): Target = when (slot) {
        TargetSlot.WORKOUT -> workout
        TargetSlot.WALK -> walk
        TargetSlot.DIET -> diet
        TargetSlot.BIBLE_READING -> bibleReading
    }

    fun with(slot: TargetSlot, target: Target): Targets = when (slot) {
        TargetSlot.WORKOUT -> copy(workout = target)
        TargetSlot.WALK -> copy(walk = target)
        TargetSlot.DIET -> copy(diet = target)
        TargetSlot.BIBLE_READING -> copy(bibleReading = target)
    }

    /** One `setWater` or `setTarget` per value that differs from [base]. */
    fun changes(base: Targets = STANDARD): List<Action> = buildList {
        if (water != base.water) add(Action.SetWater(water.goal, water.glass))
        for (slot in TargetSlot.entries) {
            val target = get(slot)
            if (target != base[slot]) add(Action.SetTarget(slot, target.name, target.amount, target.unit, target.icon))
        }
    }

    companion object {
        /**
         * The original five: 4,000 ml in 450 ml glasses, a 45-minute workout, a 45-minute walk,
         * a clean diet and 10 pages of the Bible. A day without target events uses these.
         */
        val STANDARD = Targets(
            WaterTarget(4_000, 450),
            Target("Workout", 45, TargetUnit.MINUTES),
            Target("Walk", 45, TargetUnit.MINUTES),
            Target("Diet"),
            Target("Bible", 10, TargetUnit.PAGES),
        )
    }
}

/** How an extra repeats (Swift `Challenge.ExtraSchedule`). */
sealed interface ExtraSchedule {
    /** A to-do: shown from its first day until the day it is ticked, carried over as late while open. */
    data object Once : ExtraSchedule
    /** Shown on these ISO weekdays, Monday = 1 through Sunday = 7. Never late. */
    data class Weekdays(val days: Set<Int>) : ExtraSchedule
    /** Shown every N days (1 is daily), counted from the day the rule applies from. Never late. */
    data class Every(val interval: Int) : ExtraSchedule

    /** The event that sets this rule for an extra, weekdays in ascending order. */
    fun action(id: UUID): Action.ScheduleExtra = when (this) {
        Once -> Action.ScheduleExtra(id)
        is Weekdays -> Action.ScheduleExtra(id, weekdays = days.sorted().map(Int::toLong))
        is Every -> Action.ScheduleExtra(id, every = interval.toLong())
    }

    companion object {
        val INTERVALS = 1L..30L

        /**
         * The rule of a `scheduleExtra` event, or null when no client accepts it: both rules, an
         * empty, repeated or out-of-range weekday, or N outside 1 to 30.
         */
        fun of(weekdays: List<Long>?, every: Long?): ExtraSchedule? = when {
            weekdays == null && every == null -> Once
            weekdays != null && every == null ->
                if (weekdays.isNotEmpty() && weekdays.toSet().size == weekdays.size && weekdays.all { it in 1L..7L }) {
                    Weekdays(weekdays.mapTo(HashSet()) { it.toInt() })
                } else null
            weekdays == null && every != null -> if (every in INTERVALS) Every(every.toInt()) else null
            else -> null
        }
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
    /** Ticks or unticks an extra for the event's day. The earliest ticked day completes a to-do. */
    data class SetExtra(val id: UUID, val completed: Boolean) : Action
    /** Sets a slot's name, amount and icon from the event's day on (see [Challenge.targets]). */
    data class SetTarget(
        val slot: TargetSlot,
        val name: String,
        val amount: Long? = null,
        val unit: TargetUnit? = null,
        val icon: String? = null,
    ) : Action
    /** Sets the daily water goal and the + button's glass from the event's day on. */
    data class SetWater(val goal: Long, val pour: Long) : Action
    /** Sets how an extra repeats from the event's day on (see [ExtraSchedule]). */
    data class ScheduleExtra(val id: UUID, val weekdays: List<Long>? = null, val every: Long? = null) : Action
}

/**
 * What recording or merging refuses this action for on its content alone, or null. [Wire]
 * treats such an event as unreadable, like an unknown kind.
 */
val Action.contentError: ChallengeError?
    get() = when (this) {
        is Action.SetTarget -> if (Target(name, amount, unit, icon).isValid(slot)) null else ChallengeError.INVALID_TARGET
        is Action.SetWater -> if (WaterTarget(goal, pour).isValid) null else ChallengeError.INVALID_TARGET
        is Action.ScheduleExtra -> if (ExtraSchedule.of(weekdays, every) == null) ChallengeError.INVALID_SCHEDULE else null
        else -> null
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
 * A personal item beside the five requirements. Never part of `isComplete`. As a to-do it
 * carries over, day by day, until it is done or archived; scheduled to repeat, it shows on
 * its scheduled days instead. Everything here derives from the extras events.
 */
data class Extra(
    val id: UUID,
    val title: String,
    /** The first challenge day it can show on: its earliest definition day, or an earlier day it was ticked on as a to-do. */
    val firstDay: Double,
    /** The day its current to-do was done, before any archive. Null while that is open, or while it repeats. */
    val completedOn: Double?,
    /** The first challenge day it is hidden from, or null while it is active. */
    val archivedFrom: Double?,
    /** Its repeat rules in day order, each from its `start` until the next one's. */
    internal val periods: List<Period>,
) {
    val isArchived: Boolean get() = archivedFrom != null
    /** Its latest repeat rule: [ExtraSchedule.Once] unless it has been scheduled. */
    val schedule: ExtraSchedule get() = periods.last().schedule

    /**
     * For a to-do period, the first day shown (in the first period, `firstDay`) and its earliest
     * ticked day. `startNumber` is `start` as a day number, where "every N" counts from.
     */
    data class Period(
        val start: Double,
        val startNumber: Long,
        val schedule: ExtraSchedule,
        val shownFrom: Double,
        val completedOn: Double?,
    )

    /** The repeat rule in force on the challenge day starting at `day`. */
    fun schedule(day: Double): ExtraSchedule = period(day).schedule

    private fun period(day: Double): Period = periods.lastOrNull { it.start <= day } ?: periods[0]

    /** Whether the challenge day starting at `day`, day number `number`, shows it. */
    internal fun isShown(day: Double, number: Long): Boolean {
        if (archivedFrom != null && day >= archivedFrom) return false
        val period = period(day)
        return when (val schedule = period.schedule) {
            ExtraSchedule.Once -> period.shownFrom <= day && (period.completedOn?.let { day <= it } ?: true)
            is ExtraSchedule.Weekdays -> period.start <= day && Challenge.isoWeekday(number) in schedule.days
            is ExtraSchedule.Every -> period.start <= day && (number - period.startNumber) % schedule.interval == 0L
        }
    }

    /** Carried over to the day starting at `day`: a to-do shown after its period's first day. A repeating extra is never late. */
    fun isLate(day: Double): Boolean {
        val period = period(day)
        return period.schedule == ExtraSchedule.Once && period.shownFrom < day
    }

    /** Still to do as of the day starting at `day`: active, and repeating or not done. */
    fun isOpen(asOf: Double): Boolean {
        if (isArchived) return false
        val period = period(asOf)
        return period.schedule != ExtraSchedule.Once || (period.completedOn?.let { it > asOf } ?: true)
    }
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
    /** The targets in force on this day. */
    val targets: Targets = Targets.STANDARD,
) {
    val waterMillilitres: Long get() = activePours.sumOf { it.millilitres }
    /** The day's own water goal: a later change never re-judges an earlier day. */
    val waterComplete: Boolean get() = waterMillilitres >= targets.water.goal
    /** The five requirements only. Extras never change it. */
    val isComplete: Boolean get() = status == DayStatus.COMPLETE
    val extrasDone: Int get() = completedExtras.size
    val extrasTotal: Int get() = extras.size
    val allExtrasDone: Boolean get() = extrasTotal > 0 && extrasDone == extrasTotal
    val intervalDuration: Double get() = intervalEnd - intervalStart
    /** Carried over: a to-do shown on a day after the first day it appeared, ticked or not. A repeating extra is never late. */
    fun isLate(extra: Extra): Boolean = extra.isLate(intervalStart)
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
            is Action.SetTarget, is Action.SetWater -> {
                action.contentError?.let { throw ChallengeException(it) }
                null
            }
            is Action.ScheduleExtra -> {
                val schedule = ExtraSchedule.of(action.weekdays, action.every)
                    ?: throw ChallengeException(ChallengeError.INVALID_SCHEDULE)
                val existing = allExtras.firstOrNull { it.id == action.id }
                    ?: throw ChallengeException(ChallengeError.UNKNOWN_EXTRA)
                if (existing.isArchived) throw ChallengeException(ChallengeError.ARCHIVED_EXTRA)
                if (existing.schedule(day(on)) == schedule) return null
                // A repeating extra is open, so scheduling a finished to-do takes a place.
                if (!existing.isOpen(day(at))) {
                    val trial = copy().also { it.activities = activities + Activity(id, day(on), at, action, null) }
                    if (trial.openExtras(at).size > MAXIMUM_ACTIVE_EXTRAS) throw ChallengeException(ChallengeError.TOO_MANY_EXTRAS)
                }
                null
            }
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
                is Action.SetTarget, is Action.SetWater -> {
                    if (event.undonePourID != null) throw ChallengeException(ChallengeError.CONFLICTING_ACTIVITY)
                    action.contentError?.let { throw ChallengeException(it) }
                }
                is Action.ScheduleExtra -> {
                    if (event.undonePourID != null) throw ChallengeException(ChallengeError.CONFLICTING_ACTIVITY)
                    action.contentError?.let { throw ChallengeException(it) }
                    if (action.id !in definedExtras) throw ChallengeException(ChallengeError.UNKNOWN_EXTRA)
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
        val targets = targets(selected)
        val allMet = pours.sumOf { it.millilitres } >= targets.water.goal && completed.size == Habit.entries.size &&
            diet == DietState.CLEAN
        val status = when {
            selected < startDate -> DayStatus.OUTSIDE_CHALLENGE
            selected > today -> DayStatus.FUTURE
            allMet -> DayStatus.COMPLETE
            selected < today -> DayStatus.MISSED
            else -> DayStatus.IN_PROGRESS
        }
        val (start, end) = calendar.interval(selected)
        val shownIDs = shown.mapTo(HashSet()) { it.id }
        return DailySummary(start, end, pours, completed, diet, status, shown, ticked.filterTo(HashSet()) { it in shownIDs }, targets)
    }

    /**
     * The targets in force on the day of `on`: the standard five, changed by every `setTarget`
     * and `setWater` dated that day or earlier. For each slot the latest dated change wins, then
     * the last in event order, so two devices changing one slot on one day resolve like
     * conflicting habit edits, and changes to different slots both survive.
     */
    fun targets(on: Double): Targets {
        val selected = day(on)
        var targets = Targets.STANDARD
        var waterDay: Double? = null
        val slotDays = HashMap<TargetSlot, Double>()
        for (activity in activities) {
            if (activity.day > selected) continue
            when (val action = activity.action) {
                is Action.SetTarget -> {
                    if (slotDays[action.slot]?.let { it > activity.day } == true) continue
                    slotDays[action.slot] = activity.day
                    targets = targets.with(action.slot, Target(action.name, action.amount, action.unit, action.icon))
                }
                is Action.SetWater -> {
                    if (waterDay?.let { it > activity.day } == true) continue
                    waterDay = activity.day
                    targets = targets.copy(water = WaterTarget(action.goal, action.pour))
                }
                else -> Unit
            }
        }
        return targets
    }

    /**
     * Every extra ever defined, archived ones included, in creation order. Order-independent
     * like [merge]: the earliest definition day, the earliest archive day and each day's last
     * tick in event order. `firstDay` is the earliest definition day, or the completion day
     * when that is earlier.
     *
     * Each repeat rule applies from its event's day, or from the definition day when that is
     * later; on one day the latest dated rule wins, then the last in event order. A to-do rule
     * after a to-do period changes nothing, and any other change starts a period: a to-do
     * period is completed only by a tick inside it (the first period also by an earlier tick),
     * so a repeating extra switched back to a to-do is a fresh open to-do from that day.
     */
    val allExtras: List<Extra>
        get() {
            val order = ArrayList<UUID>()
            val titles = HashMap<UUID, String>()
            val defined = HashMap<UUID, Double>()
            val archived = HashMap<UUID, Double>()
            val ticks = HashMap<UUID, HashMap<Double, Boolean>>()
            val schedules = HashMap<UUID, ArrayList<Pair<Double, ExtraSchedule>>>()
            for (activity in activities) {
                when (val action = activity.action) {
                    is Action.DefineExtra -> {
                        if (titles[action.id] == null) order.add(action.id)
                        titles[action.id] = action.title
                        defined[action.id] = minOf(defined[action.id] ?: activity.day, activity.day)
                    }
                    is Action.ArchiveExtra -> archived[action.id] = minOf(archived[action.id] ?: activity.day, activity.day)
                    is Action.SetExtra -> ticks.getOrPut(action.id) { HashMap() }[activity.day] = action.completed
                    is Action.ScheduleExtra -> ExtraSchedule.of(action.weekdays, action.every)?.let {
                        schedules.getOrPut(action.id) { ArrayList() }.add(activity.day to it)
                    }
                    else -> Unit
                }
            }
            return order.mapNotNull { id ->
                val title = titles[id] ?: return@mapNotNull null
                val definedOn = defined[id] ?: return@mapNotNull null
                // A tick from its archive day on is kept as history but never completes it.
                val ticked = ticks[id]?.filter { (day, value) -> value && (archived[id]?.let { day < it } ?: true) }?.keys
                    ?: emptySet()
                val changes = HashMap<Double, Pair<Double, ExtraSchedule>>()
                for ((dated, schedule) in schedules[id] ?: emptyList()) {
                    val from = maxOf(dated, definedOn)
                    if (changes[from]?.let { it.first > dated } == true) continue
                    changes[from] = dated to schedule
                }
                val sorted = changes.keys.sorted().map { it to changes.getValue(it).second }
                val withFirst = if (sorted.firstOrNull()?.first != definedOn) listOf(definedOn to ExtraSchedule.Once) + sorted else sorted
                val starts = withFirst.filterIndexed { index, (_, schedule) ->
                    index == 0 || schedule != ExtraSchedule.Once || withFirst[index - 1].second != ExtraSchedule.Once
                }
                val periods = starts.mapIndexed { index, (start, schedule) ->
                    val end = starts.getOrNull(index + 1)?.first
                    if (schedule != ExtraSchedule.Once) {
                        Extra.Period(start, dayNumber(start), schedule, start, null)
                    } else {
                        val completedOn = ticked.filter { day -> (index == 0 || day >= start) && (end?.let { day < it } ?: true) }.minOrNull()
                        val shownFrom = if (index == 0) minOf(start, completedOn ?: start) else start
                        Extra.Period(start, dayNumber(start), ExtraSchedule.Once, shownFrom, completedOn)
                    }
                }
                val latest = periods.last()
                Extra(id, title, periods[0].shownFrom, if (latest.schedule == ExtraSchedule.Once) latest.completedOn else null,
                    archived[id], periods)
            }
        }

    /**
     * The extras shown for the day of `asOf`, in creation order, until the day each is archived:
     * a to-do from its first day through its completion day, carried over while open; a
     * repeating extra on its scheduled days.
     */
    fun extras(asOf: Double): List<Extra> {
        val selected = day(asOf)
        val number = dayNumber(selected)
        return allExtras.filter { it.isShown(selected, number) }
    }

    /** Active, and repeating on that day or a to-do not completed on or before it: what the cap counts. */
    fun openExtras(asOf: Double): List<Extra> {
        val selected = day(asOf)
        return allExtras.filter { it.isOpen(selected) }
    }

    /** The calendar date of `instant` in the challenge's zone as days since 1970-01-01. */
    internal fun dayNumber(instant: Double): Long = calendar.localDate(instant).toEpochDay()

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
        const val MAXIMUM_TARGET_NAME_LENGTH = 20
        private const val MAXIMUM_TARGET_NAME_SCALARS = 80
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

        /** The ISO weekday (Monday = 1 through Sunday = 7) of a day number; day 0 was a Thursday. */
        internal fun isoWeekday(number: Long): Int = (Math.floorMod(number, 7L) + 3).toInt() % 7 + 1

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
        fun extraTitle(raw: String): String? = label(raw, MAXIMUM_EXTRA_TITLE_LENGTH)

        /**
         * The stored form of a slot's name: trimmed, 1 to 20 characters, one line, and at most 80
         * Unicode scalars (what PostgreSQL's `char_length` counts), so the server never refuses it.
         */
        fun targetName(raw: String): String? =
            label(raw, MAXIMUM_TARGET_NAME_LENGTH)?.takeIf { it.codePointCount(0, it.length) <= MAXIMUM_TARGET_NAME_SCALARS }

        /** An icon id: 1 to 16 lower-case ASCII letters. */
        fun isIconID(id: String): Boolean = id.length in 1..16 && id.all { it in 'a'..'z' }

        private fun label(raw: String, maximum: Int): String? {
            val title = trimWhitespaceAndNewlines(raw)
            val length = graphemeCount(title)
            if (length < 1 || length > maximum) return null
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

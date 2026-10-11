package app.dailychallenge.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.outlined.Archive
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.automirrored.outlined.DirectionsWalk
import androidx.compose.material.icons.outlined.Eco
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.FitnessCenter
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.dailychallenge.core.Action
import app.dailychallenge.core.Activity
import app.dailychallenge.core.DayStatus
import app.dailychallenge.core.DietState
import app.dailychallenge.core.Habit
import app.dailychallenge.core.Tracker
import java.time.LocalDate

/**
 * History: the month calendar, the selected day's card with its explicit Edit unlock, and the
 * day's activity, newest first. Same rules as the Mac and iPhone: selecting a day is not an
 * edit; corrections need the pencil and recalculate streaks and milestones.
 */
@Composable
fun HistoryScreen(tracker: Tracker) {
    tracker.observe()
    val calendar = tracker.dates.calendar
    var month by remember { mutableStateOf(calendar.localDate(tracker.selectedDay).withDayOfMonth(1)) }
    LaunchedEffect(tracker.selectedDay) { month = calendar.localDate(tracker.selectedDay).withDayOfMonth(1) }
    PhoneScreen {
        PhoneHeader("History") { SyncChip(tracker) }
        GlassCard {
            MonthCalendar(tracker, month, { month = it }, Modifier.padding(horizontal = Size.sectionHorizontal, vertical = 14.dp))
            Hairline()
            DayCard(tracker, Modifier.padding(horizontal = Size.sectionHorizontal, vertical = Size.sectionVertical).testTag("history-day"))
        }
        ErrorBanner(tracker)
        GlassCard { ActivityList(tracker) }
    }
}

private fun statusName(status: DayStatus) = when (status) {
    DayStatus.COMPLETE -> "Complete"
    DayStatus.MISSED -> "Missed"
    DayStatus.IN_PROGRESS -> "In progress"
    DayStatus.FUTURE -> "Future"
    DayStatus.OUTSIDE_CHALLENGE -> "Outside challenge"
}

private fun statusIcon(status: DayStatus): ImageVector = when (status) {
    DayStatus.COMPLETE -> Icons.Filled.Check
    DayStatus.MISSED -> Icons.Filled.Close
    DayStatus.IN_PROGRESS -> Icons.Outlined.Schedule
    else -> Icons.Filled.Remove
}

@Composable
private fun MonthCalendar(tracker: Tracker, month: LocalDate, onMonth: (LocalDate) -> Unit, modifier: Modifier) {
    tracker.observe()

    val calendar = tracker.dates.calendar
    val first = calendar.localDate(tracker.challenge?.startDate ?: tracker.today).withDayOfMonth(1)
    val last = calendar.localDate(tracker.today).withDayOfMonth(1)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            RoundIconButton(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Previous month", { onMonth(month.minusMonths(1)) },
                enabled = month > first, size = 36.dp)
            Text(tracker.dates.label(calendar.startOf(month), "MMMM yyyy"), style = Type.appName, color = P.textPrimary,
                modifier = Modifier.weight(1f).semantics { heading() }, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            RoundIconButton(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Next month", { onMonth(month.plusMonths(1)) },
                enabled = month < last, size = 36.dp)
        }
        Row(Modifier.fillMaxWidth()) {
            listOf("M", "T", "W", "T", "F", "S", "S").forEach {
                Text(it, style = Type.ringLabel, color = P.textSecondary, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    modifier = Modifier.weight(1f))
            }
        }
        // Weeks start on Monday, as on every device.
        val blanks = month.dayOfWeek.value - 1
        val cells: List<LocalDate?> = List(blanks) { null } + (1..month.lengthOfMonth()).map { month.withDayOfMonth(it) }
        cells.chunked(7).forEach { week ->
            Row(Modifier.fillMaxWidth()) {
                for (index in 0 until 7) {
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                        week.getOrNull(index)?.let { DayCell(tracker, it) } ?: Spacer(Modifier.height(36.dp))
                    }
                }
            }
        }
    }
}

/**
 * Each state has its own shape: complete (green disc), missed (red ring), today (blue ring and
 * halo), selected (ink disc), future or outside the challenge (faint numeral).
 */
@Composable
private fun DayCell(tracker: Tracker, date: LocalDate) {
    tracker.observe()

    val calendar = tracker.dates.calendar
    val day = calendar.startOf(date)
    val state = tracker.challenge?.summary(day, tracker.now)?.status ?: DayStatus.OUTSIDE_CHALLENGE
    val selected = day == tracker.selectedDay
    val isToday = day == tracker.today
    val allowed = state != DayStatus.OUTSIDE_CHALLENGE && state != DayStatus.FUTURE
    val numberStyle = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum")
    val palette = P
    val (fill, border, text) = when {
        isToday -> Triple(if (state == DayStatus.COMPLETE) palette.done else Color.Transparent, palette.water,
            if (state == DayStatus.COMPLETE) palette.onDone else palette.textPrimary)
        selected -> Triple(palette.textPrimary, Color.Transparent, palette.textInverse)
        state == DayStatus.COMPLETE -> Triple(palette.done, Color.Transparent, palette.onDone)
        state == DayStatus.MISSED -> Triple(Color.Transparent, palette.dangerRing, palette.danger)
        allowed -> Triple(palette.controlFill, Color.Transparent, palette.textPrimary)
        else -> Triple(Color.Transparent, Color.Transparent, palette.futureDay)
    }
    Box(
        Modifier.size(44.dp).clip(CircleShape)
            .clickable(enabled = allowed, role = Role.Button) { tracker.selectHistoryDay(day) }
            .semantics {
                contentDescription = "${tracker.dates.label(day, "d MMMM yyyy")}, ${statusName(state)}"
                this.selected = selected
            },
        contentAlignment = Alignment.Center,
    ) {
        if (isToday) Box(Modifier.size(41.dp).border(4.dp, palette.focusHalo, CircleShape))
        Box(Modifier.size(36.dp).clip(CircleShape).background(fill)
            .border(if (isToday) 2.dp else 1.5.dp, border, CircleShape), contentAlignment = Alignment.Center) {
            Text("${date.dayOfMonth}", style = numberStyle, color = text)
        }
    }
}

@Composable
private fun DayCard(tracker: Tracker, modifier: Modifier) {
    tracker.observe()

    val summary = tracker.summary
    Column(modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            // The date and badge share what the edit chip leaves; only the date gives way.
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(tracker.dates.label(tracker.selectedDay, "EEE d MMM"), style = Type.screenTitle, color = P.textPrimary, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                val status = summary?.status ?: DayStatus.OUTSIDE_CHALLENGE
                if (tracker.selectedDay == tracker.today) {
                    Badge("Today", fill = P.accentTint, foreground = P.accentText, height = 28.dp,
                        modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = "Today, ${statusName(status)}" })
                } else {
                    Badge(statusName(status), statusIcon(status),
                        fill = when (status) { DayStatus.COMPLETE -> P.doneTint; DayStatus.MISSED -> P.dangerTint; else -> P.controlFill },
                        foreground = when (status) { DayStatus.COMPLETE -> P.doneText; DayStatus.MISSED -> P.danger; else -> P.textSecondary },
                        height = 28.dp)
                }
            }
            EditChip(tracker)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.WaterDrop, null, tint = P.water, modifier = Modifier.size(18.dp))
            val ml = summary?.waterMillilitres ?: 0
            Row(Modifier.semantics(mergeDescendants = true) { contentDescription = "$ml of 4,000 millilitres" },
                verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("${formatNumber(ml)} ml", style = Type.streak.copy(fontFeatureSettings = "tnum"), color = P.textPrimary)
                Text("/ 4,000", style = Type.caption, color = if (summary?.waterComplete == true) P.doneText else P.textSecondary,
                    modifier = Modifier.padding(bottom = 3.dp))
            }
        }
        WaterControls(tracker)
        HabitControls(tracker)
        if ((summary?.extrasTotal ?: 0) > 0) {
            Hairline()
            ExtrasHeading(tracker)
            ExtrasChecklist(tracker)
            if (!tracker.canEdit) Text("Select Edit this day to correct these ticks.", style = Type.caption, color = P.textTertiary)
        }
    }
}

/** An amber pencil while the day is editable, otherwise the button that unlocks corrections for a past day. */
@Composable
private fun EditChip(tracker: Tracker) {
    tracker.observe()

    if (tracker.canEdit) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(P.amberTint).border(1.5.dp, P.amber.copy(alpha = 0.7f), CircleShape)
            .semantics { contentDescription = if (tracker.isEditingHistory) "Editing this day" else "Editing today" }
            .testTag("history-editing"), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Edit, null, tint = P.amberText, modifier = Modifier.size(17.dp))
        }
    } else {
        val status = tracker.summary?.status
        if (status != null && status != DayStatus.FUTURE && status != DayStatus.OUTSIDE_CHALLENGE) {
            RoundIconButton(Icons.Filled.Edit, "Edit this day. Allows corrections to this day; streaks and milestones recalculate.",
                tracker::enableCorrections, size = 36.dp, modifier = Modifier.testTag("history-edit"))
        }
    }
}

private enum class PillState { PENDING, DONE, MISSED }

/** Four habit pills (44 dp): pending, done (green and check), missed (red and ×). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun HabitControls(tracker: Tracker) {
    tracker.observe()

    val summary = tracker.summary
    val closed = summary?.status == DayStatus.MISSED
    @Composable
    fun pill(icon: ImageVector, state: PillState, label: String, value: String, modifier: Modifier, onLongClick: (() -> Unit)? = null,
             onClick: () -> Unit) {
        val palette = P
        val foreground = when (state) { PillState.DONE -> palette.doneText; PillState.MISSED -> palette.danger; PillState.PENDING -> palette.textSecondary }
        Row(
            modifier.height(44.dp).clip(CircleShape)
                .background(when (state) { PillState.DONE -> palette.doneTint; PillState.MISSED -> palette.dangerTint; PillState.PENDING -> palette.controlFill })
                .border(1.5.dp, when (state) {
                    PillState.DONE -> palette.done.copy(alpha = 0.55f); PillState.MISSED -> palette.dangerRing.copy(alpha = 0.6f)
                    PillState.PENDING -> palette.hairline
                }, CircleShape)
                .combinedClickable(enabled = tracker.canEdit, role = Role.Button, onLongClick = onLongClick, onClick = onClick)
                .semantics(mergeDescendants = true) { contentDescription = label; stateDescription = value },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        ) {
            Icon(icon, null, tint = foreground, modifier = Modifier.size(18.dp))
            when (state) {
                PillState.DONE -> Icon(Icons.Filled.Check, null, tint = foreground, modifier = Modifier.size(15.dp))
                PillState.MISSED -> Icon(Icons.Filled.Close, null, tint = foreground, modifier = Modifier.size(15.dp))
                PillState.PENDING -> Unit
            }
        }
    }
    @Composable
    fun habit(habit: Habit, title: String, detail: String, modifier: Modifier) {
        val complete = summary?.completedHabits?.contains(habit) == true
        pill(ActivityWords.icon(habit), if (complete) PillState.DONE else if (closed) PillState.MISSED else PillState.PENDING,
            "$title, $detail", if (complete) "Complete" else "Not complete", modifier) { tracker.toggle(habit) }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        habit(Habit.WORKOUT, "Workout", "45 min, home or gym", Modifier.weight(1f))
        habit(Habit.WALK, "Walk", "45 minutes", Modifier.weight(1f))
        val diet = summary?.diet ?: DietState.PENDING
        var menu by rememberSaveable { mutableStateOf(false) }
        Box(Modifier.weight(1f)) {
            pill(Icons.Outlined.Eco,
                if (diet == DietState.CLEAN) PillState.DONE else if (diet == DietState.MISSED || closed) PillState.MISSED else PillState.PENDING,
                "Clean diet, your own rules", diet.wire, Modifier.fillMaxWidth(), onLongClick = { menu = true }) {
                tracker.setDiet(when (diet) { DietState.PENDING -> DietState.CLEAN; DietState.CLEAN -> DietState.MISSED; DietState.MISSED -> DietState.PENDING })
            }
            DropdownMenu(menu, { menu = false }) {
                listOf(DietState.PENDING to "Pending", DietState.CLEAN to "Clean", DietState.MISSED to "Missed").forEach { (state, label) ->
                    DropdownMenuItem({ Text(label) }, onClick = { tracker.setDiet(state); menu = false }, enabled = tracker.canEdit)
                }
            }
        }
        habit(Habit.BIBLE_READING, "Bible", "10 pages", Modifier.weight(1f))
    }
}

@Composable
private fun ActivityList(tracker: Tracker) {
    tracker.observe()

    val history = tracker.history
    Column(Modifier.padding(horizontal = Size.sectionHorizontal, vertical = 4.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp)
            .semantics(mergeDescendants = true) { contentDescription = "Activity and corrections, ${history.size}"; heading() },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Outlined.Schedule, null, tint = P.textSecondary, modifier = Modifier.size(18.dp))
            Eyebrow("Activity", style = Type.caption)
            Badge("${history.size}", height = 22.dp)
        }
        if (history.isEmpty()) {
            Text("No activity recorded. Closed unrecorded days are missed.", style = Type.caption, color = P.textTertiary,
                modifier = Modifier.padding(bottom = 12.dp))
        } else {
            history.forEach { activity ->
                val (icon, tint) = ActivityWords.icon(activity)
                Row(Modifier.fillMaxWidth().heightIn(min = 36.dp).semantics(mergeDescendants = true) {
                    contentDescription = "${ActivityWords.long(activity)}, edited ${tracker.dates.label(activity.recordedAt, "d MMM, HH:mm")}"
                }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(icon, null, tint = tint, modifier = Modifier.width(22.dp).size(18.dp))
                    Text(ActivityWords.short(activity), style = Type.field, color = P.textPrimary, modifier = Modifier.weight(1f))
                    Text(tracker.dates.label(activity.recordedAt, "HH:mm"), style = Type.caption.copy(fontFeatureSettings = "tnum"),
                        color = P.textTertiary)
                }
            }
        }
    }
}

/** Activity wording, as on the Mac and iPhone. */
object ActivityWords {
    fun habitName(habit: Habit) = when (habit) { Habit.WORKOUT -> "Workout"; Habit.WALK -> "Walk"; Habit.BIBLE_READING -> "Bible reading" }

    fun icon(habit: Habit): ImageVector = when (habit) {
        Habit.WORKOUT -> Icons.Outlined.FitnessCenter
        Habit.WALK -> Icons.AutoMirrored.Outlined.DirectionsWalk
        Habit.BIBLE_READING -> Icons.AutoMirrored.Outlined.MenuBook
    }

    @Composable
    fun icon(activity: Activity): Pair<ImageVector, Color> = when (val action = activity.action) {
        is Action.Pour -> Icons.Filled.WaterDrop to P.water
        Action.UndoLatestPour -> Icons.AutoMirrored.Filled.Undo to P.textSecondary
        is Action.SetDiet -> Icons.Outlined.Eco to when (action.state) { DietState.CLEAN -> P.done; DietState.MISSED -> P.danger; else -> P.textTertiary }
        is Action.SetHabit -> icon(action.habit) to if (action.completed) P.done else P.textTertiary
        is Action.DefineExtra -> Icons.Filled.Checklist to P.textSecondary
        is Action.ArchiveExtra -> Icons.Outlined.Archive to P.textSecondary
        is Action.SetExtra -> Icons.Outlined.CheckCircle to if (action.completed) P.done else P.textTertiary
    }

    fun short(activity: Activity): String = when (val action = activity.action) {
        is Action.Pour -> "+${formatNumber(action.millilitres)} ml"
        Action.UndoLatestPour -> "Undid pour"
        is Action.SetDiet -> "Diet ${action.state.wire}"
        is Action.SetHabit -> "${habitName(action.habit)} ${if (action.completed) "complete" else "not complete"}"
        is Action.DefineExtra -> "Extra named “${action.title}”"
        is Action.ArchiveExtra -> "Archived extra"
        is Action.SetExtra -> "Extra ${if (action.completed) "done" else "not done"}"
    }

    fun long(activity: Activity): String = when (val action = activity.action) {
        is Action.Pour -> "Added ${formatNumber(action.millilitres)} ml"
        Action.UndoLatestPour -> "Undid a water pour"
        is Action.SetDiet -> "Diet set to ${action.state.wire}"
        is Action.SetHabit -> "${habitName(action.habit)} set to ${if (action.completed) "complete" else "not complete"}"
        is Action.DefineExtra -> "Extra named “${action.title}”"
        is Action.ArchiveExtra -> "Archived extra"
        is Action.SetExtra -> "Extra ${if (action.completed) "done" else "not done"}"
    }
}


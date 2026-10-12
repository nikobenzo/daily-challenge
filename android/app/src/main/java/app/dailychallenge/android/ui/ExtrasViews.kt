package app.dailychallenge.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.outlined.Archive
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.automirrored.outlined.Label
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import app.dailychallenge.android.AppGraph
import app.dailychallenge.core.Challenge
import app.dailychallenge.core.Extra
import app.dailychallenge.core.ExtraSchedule
import app.dailychallenge.core.Tracker
import java.util.UUID

/** Optional to-dos that carry over until done, and repeating ones; their count comes from the selected day's summary. */
@Composable
fun ExtrasSection(graph: AppGraph) {
    val tracker = graph.tracker
    tracker.observe()
    Column(Modifier.padding(horizontal = Size.sectionHorizontal, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if ((tracker.summary?.extrasTotal ?: 0) == 0) {
            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(role = Role.Button) { graph.manageExtrasRequested = true }
                .testTag("extras-empty"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.Checklist, null, tint = P.textSecondary, modifier = Modifier.size(20.dp))
                Text("Extras · Add your own to-dos", style = Type.field, color = P.textSecondary)
            }
        } else {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                ExtrasHeading(tracker, Modifier.weight(1f))
                RoundIconButton(Icons.Outlined.EditNote, "Manage extras", { graph.manageExtrasRequested = true }, size = 44.dp,
                    modifier = Modifier.testTag("extras-manage"))
            }
            ExtrasChecklist(tracker)
        }
    }
}

@Composable
fun ExtrasHeading(tracker: Tracker, modifier: Modifier = Modifier) {
    tracker.observe()

    val done = tracker.summary?.extrasDone ?: 0
    val total = tracker.summary?.extrasTotal ?: 0
    Row(modifier.semantics(mergeDescendants = true) { contentDescription = "Extras, $done of $total done"; heading() }.testTag("extras-count"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Filled.Checklist, null, tint = P.textSecondary, modifier = Modifier.size(20.dp))
        Text("Extras · $done/$total", style = Type.rowLabel, color = P.textSecondary)
    }
}

/**
 * The selected day's extras: carried-over ones marked "Late", completed ones gone from later
 * days, extras archived after that day, and repeating ones on their days with how they repeat.
 */
@Composable
fun ExtrasChecklist(tracker: Tracker) {
    tracker.observe()

    val summary = tracker.summary ?: return
    Column {
        summary.extras.forEach { extra ->
            val done = extra.id in summary.completedExtras
            val late = summary.isLate(extra)
            val repeat = extra.schedule(summary.intervalStart).takeIf { it != ExtraSchedule.Once }?.let { RepeatWords.caption(it, sentence = true) }
            Row(
                Modifier.fillMaxWidth().heightIn(min = 44.dp)
                    .clickable(enabled = tracker.canEdit, role = Role.Checkbox) { tracker.toggleExtra(extra.id) }
                    .padding(vertical = 4.dp)
                    .semantics(mergeDescendants = true) {
                        contentDescription = listOfNotNull(extra.title, "late".takeIf { late }, repeat).joinToString(", ")
                        stateDescription = if (done) "Done" else "Not done"
                    }
                    .testTag("extra-${Challenge.uuidString(extra.id)}"),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                TickCircle(done)
                Text(extra.title, style = Type.field, color = if (done) P.textSecondary else P.textPrimary, modifier = Modifier.weight(1f, fill = false))
                if (late) LateMarker()
                repeat?.let { Text(it, style = Type.caption, color = P.textSecondary, maxLines = 1) }
                Spacer(Modifier.weight(1f))
            }
        }
    }
}

/** How a repeat rule reads: "Every day", "Weekdays", "Sundays", "Mon, Wed, Fri", "Every 2 days", "Once". */
object RepeatWords {
    private val names = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")

    /** `sentence` gives the lower-case form used after a title: "every day", "weekdays", "Sundays". */
    fun caption(schedule: ExtraSchedule, sentence: Boolean = false): String {
        val text = when (schedule) {
            ExtraSchedule.Once -> "Once"
            is ExtraSchedule.Every -> if (schedule.interval == 1) "Every day" else "Every ${schedule.interval} days"
            is ExtraSchedule.Weekdays -> when (schedule.days) {
                (1..7).toSet() -> "Every day"
                (1..5).toSet() -> "Weekdays"
                setOf(6, 7) -> "Weekends"
                else -> if (schedule.days.size == 1) names[schedule.days.single() - 1] + "s"
                    else schedule.days.sorted().joinToString(", ") { names[it - 1].take(3) }
            }
        }
        // Day names keep their capital.
        return if (sentence && (text.startsWith("Every") || text.startsWith("Week") || text == "Once")) text.lowercase() else text
    }

    /** For TalkBack: day names in full. */
    fun spoken(schedule: ExtraSchedule): String =
        if (schedule is ExtraSchedule.Weekdays && schedule.days.size in 2..4) schedule.days.sorted().joinToString(", ") { names[it - 1] }
        else caption(schedule)

    fun dayName(day: Int) = names[day - 1]
}

private enum class RepeatMode(val label: String) { ONCE("Once"), DAILY("Every day"), WEEKDAYS("Weekdays"), DAYS("Choose days"), EVERY("Every N days") }

private fun ExtraSchedule.mode(): RepeatMode = when (this) {
    ExtraSchedule.Once -> RepeatMode.ONCE
    is ExtraSchedule.Every -> if (interval == 1) RepeatMode.DAILY else RepeatMode.EVERY
    is ExtraSchedule.Weekdays -> if (days == (1..5).toSet()) RepeatMode.WEEKDAYS else RepeatMode.DAYS
}

/**
 * Once, every day, weekdays, chosen days or every N days (2 to 30). Chosen days with none
 * selected is not a rule, so the caller's Save stays off and this says why.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RepeatPicker(schedule: ExtraSchedule, onChange: (ExtraSchedule) -> Unit) {
    // Choosing Monday to Friday by hand stays on "Choose days" while this picker is open.
    var choosing by remember { mutableStateOf(schedule.mode() == RepeatMode.DAYS) }
    val mode = if (choosing && schedule is ExtraSchedule.Weekdays) RepeatMode.DAYS else schedule.mode()
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Eyebrow("Repeat")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            RepeatMode.entries.forEach { option ->
                ChoiceChip(option.label, option == mode, {
                    choosing = option == RepeatMode.DAYS
                    if (option != mode) onChange(when (option) {
                        RepeatMode.ONCE -> ExtraSchedule.Once
                        RepeatMode.DAILY -> ExtraSchedule.Every(1)
                        RepeatMode.WEEKDAYS -> ExtraSchedule.Weekdays((1..5).toSet())
                        RepeatMode.DAYS -> ExtraSchedule.Weekdays((schedule as? ExtraSchedule.Weekdays)?.days ?: setOf(6, 7))
                        RepeatMode.EVERY -> ExtraSchedule.Every(2)
                    })
                }, Modifier.testTag("repeat-${option.name.lowercase()}"))
            }
        }
        when (mode) {
            RepeatMode.DAYS -> {
                val days = (schedule as ExtraSchedule.Weekdays).days
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    (1..7).forEach { day ->
                        val on = day in days
                        Box(
                            Modifier.size(40.dp).clip(CircleShape).background(if (on) P.accentTint else P.controlFill)
                                .border(1.5.dp, if (on) P.accentText.copy(alpha = 0.6f) else Color.Transparent, CircleShape)
                                .clickable(role = Role.Checkbox) { onChange(ExtraSchedule.Weekdays(if (on) days - day else days + day)) }
                                .semantics { contentDescription = RepeatWords.dayName(day); stateDescription = if (on) "Chosen" else "Not chosen" }
                                .testTag("repeat-day-$day"),
                            contentAlignment = Alignment.Center,
                        ) { Text(RepeatWords.dayName(day).take(1), style = Type.badge, color = if (on) P.accentText else P.textPrimary) }
                    }
                }
                if (days.isEmpty()) FieldError("Choose at least one day.")
            }
            RepeatMode.EVERY -> {
                val interval = (schedule as ExtraSchedule.Every).interval
                Stepper("every $interval days", "Every $interval days", { onChange(ExtraSchedule.Every(interval - 1)) },
                    { onChange(ExtraSchedule.Every(interval + 1)) }, interval > 2, interval < ExtraSchedule.INTERVALS.last.toInt(),
                    "Fewer days between", "More days between", "repeat-interval")
            }
            else -> Unit
        }
        Text(if (mode == RepeatMode.ONCE) "A to-do: it carries over, marked Late, until you tick it."
            else "Shows on its days from today. A missed day doesn't carry over and is never late.",
            style = Type.caption, color = P.textTertiary)
    }
}

private fun ExtraSchedule.isValid() = this !is ExtraSchedule.Weekdays || days.isNotEmpty()

private fun titleHelp(title: String): Pair<String, Boolean> {
    val invalid = title.isNotEmpty() && Challenge.extraTitle(title) == null
    return (if (invalid) "Use a name of 1 to 40 characters on one line." else "One line, 1 to 40 characters.") to invalid
}

@Composable
private fun TitleHelp(title: String) {
    val (text, invalid) = titleHelp(title)
    Text(text, style = Type.caption, color = if (invalid) P.danger else P.textTertiary)
}

/** One scrolling management sheet used by Today and Account: add, edit (name and repeat) and archive. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ManageExtrasSheet(tracker: Tracker, initialEditing: String? = null, onDismiss: () -> Unit) {
    tracker.observe()
    var newTitle by rememberSaveable { mutableStateOf("") }
    var newSchedule by remember { mutableStateOf<ExtraSchedule>(ExtraSchedule.Once) }
    var renaming by remember { mutableStateOf(tracker.activeExtras.firstOrNull { it.title == initialEditing }?.id) }
    var renameTitle by rememberSaveable { mutableStateOf(initialEditing ?: "") }
    var editSchedule by remember { mutableStateOf(tracker.activeExtras.firstOrNull { it.title == initialEditing }?.schedule ?: ExtraSchedule.Once) }
    var archiving by remember { mutableStateOf<Extra?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val active = tracker.activeExtras

    fun add() {
        error = tracker.addExtra(newTitle, newSchedule)
        if (error == null) { newTitle = ""; newSchedule = ExtraSchedule.Once }
    }

    AppSheet(onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Manage extras", style = Type.appName, color = P.textPrimary, modifier = Modifier.weight(1f).semantics { heading() })
                TextButton(onDismiss, modifier = Modifier.testTag("extras-done")) { Text("Done", style = Type.pill, color = P.accentText) }
            }
            GlassCard {
                Column(Modifier.padding(Size.sectionHorizontal), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("${active.size}/${Challenge.MAXIMUM_ACTIVE_EXTRAS} extras", style = Type.rowLabel, color = P.textPrimary,
                        modifier = Modifier.testTag("extras-active-count"))
                    Text("Things of your own to tick: a to-do carries over until done, and a repeating one shows on its days. " +
                        "They never count toward the five or your streak.", style = Type.caption, color = P.textSecondary)
                    if (tracker.canAddExtra) {
                        DesignField(newTitle, { newTitle = it }, "New extra", Icons.AutoMirrored.Outlined.Label, imeAction = ImeAction.Done,
                            onSubmit = { if (Challenge.extraTitle(newTitle) != null && newSchedule.isValid()) add() }, testTag = "extras-new-title")
                        TitleHelp(newTitle)
                        if (newTitle.isNotEmpty()) RepeatPicker(newSchedule) { newSchedule = it }
                        TintedPill("Add extra", ::add, enabled = Challenge.extraTitle(newTitle) != null && newSchedule.isValid(), height = 44.dp,
                            expands = true, modifier = Modifier.testTag("extras-add"))
                    } else {
                        Row(Modifier.testTag("extras-cap"), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Outlined.Info, null, tint = P.amberText, modifier = Modifier.size(16.dp))
                            Text("Up to 10 extras. Archive one to add another.", style = Type.caption, color = P.amberText)
                        }
                    }
                    error?.let { FieldError(it) }
                }
            }
            if (active.isNotEmpty()) {
                GlassCard {
                    active.forEachIndexed { index, extra ->
                        if (index > 0) Hairline()
                        Column(Modifier.fillMaxWidth().padding(Size.sectionHorizontal), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (renaming == extra.id) {
                                DesignField(renameTitle, { renameTitle = it }, "Name", Icons.Filled.Edit, imeAction = ImeAction.Done,
                                    testTag = "extras-rename-title")
                                TitleHelp(renameTitle)
                                RepeatPicker(editSchedule) { editSchedule = it }
                                if (editSchedule != extra.schedule) {
                                    Text("Changes apply from today. Earlier days keep how they showed.", style = Type.caption, color = P.textSecondary)
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    TintedPill("Save", {
                                        error = tracker.editExtra(extra.id, renameTitle, editSchedule)
                                        if (error == null) renaming = null
                                    }, Modifier.weight(1f).testTag("extras-save"),
                                        enabled = Challenge.extraTitle(renameTitle) != null && editSchedule.isValid(), height = 44.dp, expands = true)
                                    TintedPill("Cancel", { renaming = null }, Modifier.weight(1f), height = 44.dp, expands = true)
                                }
                            } else {
                                val repeat = extra.schedule
                                Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {
                                    contentDescription = "${extra.title}, ${RepeatWords.spoken(repeat)}"
                                }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text(extra.title, style = Type.field, color = P.textPrimary, modifier = Modifier.weight(1f))
                                    Text(RepeatWords.caption(repeat), style = Type.caption, color = P.textSecondary, maxLines = 1,
                                        modifier = Modifier.testTag("extras-repeat-${Challenge.uuidString(extra.id)}"))
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    TintedPill("Edit", { error = null; renameTitle = extra.title; editSchedule = extra.schedule; renaming = extra.id },
                                        Modifier.weight(1f).semantics { contentDescription = "Edit ${extra.title}" }
                                            .testTag("extras-edit-${Challenge.uuidString(extra.id)}"),
                                        icon = Icons.Filled.Edit, height = 44.dp, expands = true)
                                    TintedPill("Archive", { error = null; renaming = null; archiving = extra },
                                        Modifier.weight(1f).semantics { contentDescription = "Archive ${extra.title}" },
                                        icon = Icons.Outlined.Archive, height = 44.dp, fill = P.dangerTint, foreground = P.danger, expands = true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    archiving?.let { extra ->
        AlertDialog(
            onDismissRequest = { archiving = null },
            title = { Text("Archive extra?") },
            text = { Text("It disappears from today on and can't be restored. Earlier days keep their ticks.") },
            confirmButton = {
                TextButton({ error = tracker.archiveExtra(extra.id); archiving = null }) { Text("Archive ${extra.title}", color = P.danger) }
            },
            dismissButton = { TextButton({ archiving = null }) { Text("Cancel") } },
            containerColor = P.solidGlass, titleContentColor = P.textPrimary, textContentColor = P.textSecondary,
        )
    }
}

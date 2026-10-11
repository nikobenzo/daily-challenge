package app.dailychallenge.android.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.automirrored.outlined.DirectionsWalk
import androidx.compose.material.icons.outlined.Eco
import androidx.compose.material.icons.outlined.FitnessCenter
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dailychallenge.android.AppGraph
import app.dailychallenge.core.DayStatus
import app.dailychallenge.core.DietState
import app.dailychallenge.core.Habit
import app.dailychallenge.core.StreakSummary
import app.dailychallenge.core.Tracker
import java.text.NumberFormat

fun formatNumber(value: Long): String = NumberFormat.getIntegerInstance().format(value)

/**
 * Today: the five ring gauges, the water jug and its controls, extras and the streak, in one
 * glass card separated by hairlines, as on the Mac and iPhone.
 */
@Composable
fun TodayScreen(graph: AppGraph, visible: Boolean) {
    val tracker = graph.tracker
    tracker.observe()
    val complete = tracker.summary?.isComplete == true
    PhoneScreen {
        PhoneHeader { if (tracker.dayNumber > 0) DayBadge(tracker) }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(tracker.dates.label(tracker.today, "EEEE d MMMM"), style = Type.link, color = P.textSecondary, modifier = Modifier.weight(1f))
            SyncChip(tracker)
        }
        GlassCard {
            RingRow(tracker, Modifier.padding(horizontal = 4.dp, vertical = Size.sectionVertical + 2.dp))
            Hairline()
            AnimatedVisibility(complete, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
                Column { CompletionBand(tracker.dayNumber); Hairline() }
            }
            Box {
                WaterSection(tracker, Modifier.padding(horizontal = Size.sectionHorizontal, vertical = Size.sectionVertical + 2.dp))
                CompletionEffect(tracker.celebration, visible, Modifier.matchParentSize()) { tracker.clearCelebration() }
            }
            Hairline()
            ExtrasSection(graph)
            Hairline()
            StreakRow(tracker.streaks, Modifier.padding(horizontal = Size.sectionHorizontal, vertical = Size.sectionVertical))
        }
        ErrorBanner(tracker)
    }
}

@Composable
fun DayBadge(tracker: Tracker) {
    tracker.observe()

    val today = tracker.challenge?.summary(tracker.today, tracker.now)
    val complete = today?.isComplete == true
    val done = today?.let { it.completedHabits.size + (if (it.waterComplete) 1 else 0) + (if (it.diet == DietState.CLEAN) 1 else 0) } ?: 0
    Badge("Day ${tracker.dayNumber}", if (complete) Icons.Filled.Check else null,
        fill = if (complete) P.doneTint else P.dayBadgeFill, foreground = if (complete) P.doneText else P.dayBadgeText, height = 30.dp,
        modifier = Modifier.semantics(mergeDescendants = true) {
            contentDescription = "Day ${tracker.dayNumber}" + if (complete) ", complete" else ", $done of 5 done"
        })
}

/**
 * WATER · WORKOUT · WALK · DIET · BIBLE. Water mirrors the jug; the four habit rings are the
 * habit controls (tap to toggle; diet cycles, and a long press chooses directly).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun RingRow(tracker: Tracker, modifier: Modifier = Modifier) {
    tracker.observe()

    val summary = tracker.summary
    val closed = summary?.status == DayStatus.MISSED
    val ml = summary?.waterMillilitres ?: 0
    val waterState = when {
        summary?.waterComplete == true -> RingState.Done
        closed -> RingState.Missed
        ml == 0L -> RingState.Pending
        else -> RingState.Progress(ml / 4_000.0)
    }
    @Composable
    fun habit(habit: Habit, title: String, detail: String, icon: ImageVector, rowModifier: Modifier) {
        val complete = summary?.completedHabits?.contains(habit) == true
        RingGauge(icon, title, if (complete) RingState.Done else if (closed) RingState.Missed else RingState.Pending,
            modifier = rowModifier
                .combinedClickable(enabled = tracker.canEdit, role = Role.Checkbox, onClick = { tracker.toggle(habit) })
                .semantics(mergeDescendants = true) {
                    contentDescription = "$title, $detail"
                    stateDescription = if (complete) "Complete" else "Not complete"
                }
                .testTag("ring-${habit.wire}"))
    }
    Row(modifier.fillMaxWidth()) {
        RingGauge(Icons.Filled.WaterDrop, "Water", waterState, showsPercent = true,
            modifier = Modifier.weight(1f).semantics(mergeDescendants = true) {
                contentDescription = "Water"
                stateDescription = "$ml of 4,000 millilitres"
            }.testTag("ring-water"))
        habit(Habit.WORKOUT, "Workout", "45 min, home or gym", Icons.Outlined.FitnessCenter, Modifier.weight(1f))
        habit(Habit.WALK, "Walk", "45 minutes", Icons.AutoMirrored.Outlined.DirectionsWalk, Modifier.weight(1f))
        val diet = summary?.diet ?: DietState.PENDING
        var menu by rememberSaveable { mutableStateOf(false) }
        Box(Modifier.weight(1f)) {
            RingGauge(Icons.Outlined.Eco, "Diet",
                if (diet == DietState.CLEAN) RingState.Done else if (diet == DietState.MISSED || closed) RingState.Missed else RingState.Pending,
                modifier = Modifier.fillMaxWidth()
                    .combinedClickable(enabled = tracker.canEdit, role = Role.Button,
                        onLongClickLabel = "Choose diet state", onLongClick = { menu = true },
                        onClick = {
                            tracker.setDiet(when (diet) { DietState.PENDING -> DietState.CLEAN; DietState.CLEAN -> DietState.MISSED; DietState.MISSED -> DietState.PENDING })
                        })
                    .semantics(mergeDescendants = true) {
                        contentDescription = "Clean diet, your own rules. Tap to cycle pending, clean and missed"
                        stateDescription = diet.wire
                    }
                    .testTag("ring-diet"))
            DropdownMenu(menu, { menu = false }) {
                listOf(DietState.PENDING to "Pending", DietState.CLEAN to "Clean", DietState.MISSED to "Missed").forEach { (state, label) ->
                    DropdownMenuItem({ Text(label) }, onClick = { tracker.setDiet(state); menu = false }, enabled = tracker.canEdit,
                        trailingIcon = { if (state == diet) Icon(Icons.Filled.Check, null) })
                }
            }
        }
        habit(Habit.BIBLE_READING, "Bible", "10 pages", Icons.AutoMirrored.Outlined.MenuBook, Modifier.weight(1f))
    }
}

/** "All five complete! / Day 12 counts toward your streak". */
@Composable
fun CompletionBand(day: Int) {
    Row(Modifier.fillMaxWidth().background(P.doneTint).padding(horizontal = Size.sectionHorizontal, vertical = 12.dp)
        .semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(Icons.Filled.Verified, null, tint = P.done, modifier = Modifier.size(30.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("All five complete!", style = Type.appName, color = P.textPrimary)
            Text("Day $day counts toward your streak", style = Type.caption, color = P.doneText)
        }
    }
}

/** The jug beside the total, then the pour controls across the full width. */
@Composable
fun WaterSection(tracker: Tracker, modifier: Modifier = Modifier) {
    tracker.observe()

    val ml = tracker.summary?.waterMillilitres ?: 0
    Column(modifier, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            WaterJug(ml, Modifier.testTag("water-jug"))
            WaterTotal(tracker)
        }
        WaterControls(tracker)
    }
}

/** "2,250 ml / 4,000" for the selected day, with the goal turning green once met. */
@Composable
fun WaterTotal(tracker: Tracker) {
    tracker.observe()

    val ml = tracker.summary?.waterMillilitres ?: 0
    val complete = tracker.summary?.waterComplete == true
    Row(Modifier.semantics(mergeDescendants = true) { contentDescription = "$ml of 4,000 millilitres" }.testTag("water-total"),
        verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("${formatNumber(ml)} ml", style = Type.hero.copy(fontFeatureSettings = "tnum"), color = P.textPrimary, maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        Text("/ 4,000", style = Type.caption, color = if (complete) P.doneText else P.textSecondary, modifier = Modifier.padding(bottom = 6.dp))
    }
}

/** −, + 450 ml and ⋯ (custom pour), for the selected day. */
@Composable
fun WaterControls(tracker: Tracker) {
    tracker.observe()

    var custom by rememberSaveable { mutableStateOf<String?>(null) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        RoundIconButton(Icons.Filled.Remove, "Undo latest water pour", tracker::undoWater, enabled = tracker.canUndo, size = 44.dp,
            modifier = Modifier.testTag("water-undo"))
        val addModifier = Modifier.weight(1f).semantics { contentDescription = "Add 450 millilitres of water" }.testTag("water-add")
        if (tracker.summary?.waterComplete == true) {
            TintedPill("450 ml", { tracker.addWater() }, addModifier, icon = Icons.Filled.Add, enabled = tracker.canEdit, height = 44.dp, expands = true)
        } else {
            PrimaryPill("450 ml", { tracker.addWater() }, addModifier, icon = Icons.Filled.Add, enabled = tracker.canEdit, height = 44.dp)
        }
        RoundIconButton(Icons.Filled.MoreHoriz, "Custom pour", { custom = "" }, enabled = tracker.canEdit, size = 44.dp,
            modifier = Modifier.testTag("water-custom"))
    }
    custom?.let { amount ->
        AlertDialog(
            onDismissRequest = { custom = null },
            title = { Text("Custom pour") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Whole millilitres, such as 250.", style = Type.caption, color = P.textSecondary)
                    DesignField(amount, { value -> custom = value.filter { it in '0'..'9' }.take(6) }, "Amount in ml", Icons.Filled.WaterDrop,
                        keyboardType = KeyboardType.Number, onSubmit = { tracker.addCustomWater(amount); custom = null }, testTag = "water-custom-amount")
                }
            },
            confirmButton = { TextButton({ tracker.addCustomWater(amount); custom = null }) { Text("Add") } },
            dismissButton = { TextButton({ custom = null }) { Text("Cancel") } },
            containerColor = P.solidGlass, titleContentColor = P.textPrimary, textContentColor = P.textPrimary,
        )
    }
}

/** Flame "12 / 75 days" with the best streak (and any 75-day milestones) as badges. */
@Composable
fun StreakRow(streaks: StreakSummary?, modifier: Modifier = Modifier) {
    val current = streaks?.current ?: 0
    val best = streaks?.best ?: 0
    val milestones = streaks?.milestones?.size ?: 0
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Filled.LocalFireDepartment, null, tint = P.amber, modifier = Modifier.size(26.dp))
        Row(Modifier.semantics(mergeDescendants = true) { contentDescription = "Current streak: $current days. Goal: 75 days." }.testTag("streak-current"),
            verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Text("$current", style = Type.streak, color = P.amberText)
            Text("/ 75 days", style = Type.link, color = P.textSecondary, modifier = Modifier.padding(bottom = 3.dp))
        }
        Spacer(Modifier.weight(1f))
        if (milestones > 0) {
            Badge("$milestones", Icons.Filled.WorkspacePremium, fill = P.doneTint, foreground = P.doneText, height = 28.dp,
                modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = "$milestones milestone" + if (milestones == 1) "" else "s" })
        }
        Badge("$best", Icons.Filled.EmojiEvents, fill = P.bestBadgeFill, foreground = P.bestBadgeText, height = 28.dp, iconColor = P.amber,
            modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = "Best streak: $best days" })
    }
}

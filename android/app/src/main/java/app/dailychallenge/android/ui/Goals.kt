package app.dailychallenge.android.ui

import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.DirectionsBike
import androidx.compose.material.icons.automirrored.outlined.DirectionsRun
import androidx.compose.material.icons.automirrored.outlined.DirectionsWalk
import androidx.compose.material.icons.automirrored.outlined.Label
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.outlined.AccessibilityNew
import androidx.compose.material.icons.outlined.AutoStories
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Eco
import androidx.compose.material.icons.outlined.FitnessCenter
import androidx.compose.material.icons.outlined.Headphones
import androidx.compose.material.icons.outlined.Pool
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.outlined.SelfImprovement
import androidx.compose.material.icons.outlined.SportsGymnastics
import androidx.compose.material.icons.outlined.Straighten
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dailychallenge.android.R
import app.dailychallenge.core.Challenge
import app.dailychallenge.core.ChallengeSyncError
import app.dailychallenge.core.Target
import app.dailychallenge.core.TargetSlot
import app.dailychallenge.core.TargetUnit
import app.dailychallenge.core.Targets
import app.dailychallenge.core.Tracker
import app.dailychallenge.core.WaterTarget

/**
 * The icon ids every client shares (custom goals plan, section 4.2), drawn with Material icons in
 * the app and as vector drawables in the widgets. An id this version does not know shows the
 * slot's default, so the list can grow later.
 */
object GoalIcons {
    class Choice(val id: String, val label: String, val vector: ImageVector, @DrawableRes val widget: Int)

    val all = listOf(
        Choice("dumbbell", "Dumbbell", Icons.Outlined.FitnessCenter, R.drawable.widget_ic_workout),
        Choice("walk", "Walking", Icons.AutoMirrored.Outlined.DirectionsWalk, R.drawable.widget_ic_walk),
        Choice("run", "Running", Icons.AutoMirrored.Outlined.DirectionsRun, R.drawable.widget_ic_run),
        Choice("bike", "Cycling", Icons.AutoMirrored.Outlined.DirectionsBike, R.drawable.widget_ic_bike),
        Choice("swim", "Swimming", Icons.Outlined.Pool, R.drawable.widget_ic_swim),
        Choice("yoga", "Yoga", Icons.Outlined.SelfImprovement, R.drawable.widget_ic_yoga),
        Choice("pilates", "Pilates", Icons.Outlined.SportsGymnastics, R.drawable.widget_ic_pilates),
        Choice("stretch", "Stretching", Icons.Outlined.AccessibilityNew, R.drawable.widget_ic_stretch),
        Choice("bible", "Bible", Icons.AutoMirrored.Outlined.MenuBook, R.drawable.widget_ic_bible),
        Choice("book", "Book", Icons.Outlined.AutoStories, R.drawable.widget_ic_book),
        Choice("headphones", "Headphones", Icons.Outlined.Headphones, R.drawable.widget_ic_headphones),
        Choice("study", "Study", Icons.Outlined.School, R.drawable.widget_ic_study),
        Choice("leaf", "Leaf", Icons.Outlined.Eco, R.drawable.widget_ic_diet),
    )

    fun default(slot: TargetSlot): String = when (slot) {
        TargetSlot.WORKOUT -> "dumbbell"
        TargetSlot.WALK -> "walk"
        TargetSlot.DIET -> "leaf"
        TargetSlot.BIBLE_READING -> "bible"
    }

    fun of(slot: TargetSlot, target: Target): Choice = all.firstOrNull { it.id == target.icon } ?: all.first { it.id == default(slot) }
}

/** The presets each slot offers (section 4.2): a name, an icon and a suggested amount the person can change. */
object GoalPresets {
    private fun preset(slot: TargetSlot, name: String, amount: Long? = null, unit: TargetUnit? = null, icon: String? = null) =
        Target(name, amount, unit, icon?.takeIf { it != GoalIcons.default(slot) })

    fun of(slot: TargetSlot): List<Target> = when (slot) {
        TargetSlot.WORKOUT -> listOf(
            Targets.STANDARD.workout, preset(slot, "Gym", 45, TargetUnit.MINUTES), preset(slot, "Run", 30, TargetUnit.MINUTES, "run"),
            preset(slot, "Cycle", 45, TargetUnit.MINUTES, "bike"), preset(slot, "Swim", 30, TargetUnit.MINUTES, "swim"),
            preset(slot, "Yoga", 30, TargetUnit.MINUTES, "yoga"), preset(slot, "Pilates", 30, TargetUnit.MINUTES, "pilates"),
            preset(slot, "HIIT", 20, TargetUnit.MINUTES),
        )
        TargetSlot.WALK -> listOf(
            Targets.STANDARD.walk, preset(slot, "Yoga", 30, TargetUnit.MINUTES, "yoga"),
            preset(slot, "Pilates", 30, TargetUnit.MINUTES, "pilates"), preset(slot, "Stretching", 15, TargetUnit.MINUTES, "stretch"),
            preset(slot, "Run", 30, TargetUnit.MINUTES, "run"), preset(slot, "Cycle", 45, TargetUnit.MINUTES, "bike"),
            preset(slot, "Steps", 10_000, TargetUnit.STEPS),
        )
        TargetSlot.DIET -> listOf(Targets.STANDARD.diet, Target("Clean eating"), Target("No sugar"), Target("No alcohol"))
        TargetSlot.BIBLE_READING -> listOf(
            Targets.STANDARD.bibleReading, preset(slot, "Book", 10, TargetUnit.PAGES, "book"),
            preset(slot, "Audiobook", 20, TargetUnit.MINUTES, "headphones"), preset(slot, "Devotional", 1, TargetUnit.CHAPTERS),
            preset(slot, "Study", 30, TargetUnit.MINUTES, "study"),
        )
    }

    /** Water's glass presets (section 4.2), then Other. */
    val glasses = listOf(250L, 330L, 450L, 500L, 750L)
}

/** How a target reads in rows, rings, the audit and TalkBack. */
object GoalWords {
    const val HOME_OR_GYM = "home or gym"

    fun slotTitle(slot: TargetSlot): String = when (slot) {
        TargetSlot.WORKOUT -> "First activity"
        TargetSlot.WALK -> "Second activity"
        TargetSlot.DIET -> "Diet"
        TargetSlot.BIBLE_READING -> "Reading"
    }

    private fun counted(amount: Long, one: String, many: String) = "${formatNumber(amount)} ${if (amount == 1L) one else many}"

    /** "45 min", "10 pages", "1 chapter", "5 km", "3 miles", "10,000 steps". */
    fun amount(target: Target): String? {
        val amount = target.amount ?: return null
        return when (target.unit ?: return null) {
            TargetUnit.MINUTES -> "${formatNumber(amount)} min"
            TargetUnit.PAGES -> counted(amount, "page", "pages")
            TargetUnit.CHAPTERS -> counted(amount, "chapter", "chapters")
            TargetUnit.KILOMETRES -> "${formatNumber(amount)} km"
            TargetUnit.MILES -> counted(amount, "mile", "miles")
            TargetUnit.STEPS -> counted(amount, "step", "steps")
        }
    }

    /** The amount with its unit in full, for TalkBack: "45 minutes", "5 kilometres". */
    fun amountSpoken(target: Target): String? {
        val amount = target.amount ?: return null
        return when (target.unit ?: return null) {
            TargetUnit.MINUTES -> counted(amount, "minute", "minutes")
            TargetUnit.KILOMETRES -> counted(amount, "kilometre", "kilometres")
            else -> amount(target)
        }
    }

    fun unitName(unit: TargetUnit): String = when (unit) {
        TargetUnit.MINUTES -> "minutes"
        TargetUnit.PAGES -> "pages"
        TargetUnit.CHAPTERS -> "chapters"
        TargetUnit.KILOMETRES -> "km"
        TargetUnit.MILES -> "miles"
        TargetUnit.STEPS -> "steps"
    }

    /** The amount a unit starts at when it is chosen. */
    fun suggested(unit: TargetUnit): Long = when (unit) {
        TargetUnit.MINUTES -> 30
        TargetUnit.PAGES -> 10
        TargetUnit.CHAPTERS -> 1
        TargetUnit.KILOMETRES -> 5
        TargetUnit.MILES -> 3
        TargetUnit.STEPS -> 10_000
    }

    fun step(unit: TargetUnit): Long = when (unit) {
        TargetUnit.MINUTES -> 5
        TargetUnit.STEPS -> 500
        else -> 1
    }

    /** "Minutes: 5 to 300." */
    fun range(unit: TargetUnit): String =
        "${unitName(unit).replaceFirstChar { it.uppercase() }}: ${formatNumber(unit.amounts.first)} to ${formatNumber(unit.amounts.last)}."

    private fun isStandardWorkout(slot: TargetSlot, target: Target) = slot == TargetSlot.WORKOUT && target == Targets.STANDARD.workout

    /** A row's or ring's detail: "45 min · home or gym", "10 pages", "Your own rules", or nothing. */
    fun detail(slot: TargetSlot, target: Target): String =
        if (slot == TargetSlot.DIET) "Your own rules"
        else listOfNotNull(amount(target), HOME_OR_GYM.takeIf { isStandardWorkout(slot, target) }).joinToString(" · ")

    /** What TalkBack reads for a slot: "Workout, 45 minutes, home or gym", "Clean diet, your own rules". */
    fun spoken(slot: TargetSlot, target: Target): String =
        if (slot == TargetSlot.DIET) {
            if (target.name == Targets.STANDARD.diet.name) "Clean diet, your own rules" else "${target.name}, your own rules"
        } else {
            listOfNotNull(target.name, amountSpoken(target), HOME_OR_GYM.takeIf { isStandardWorkout(slot, target) }).joinToString(", ")
        }

    /** "4,000 ml · 450 ml glass". */
    fun water(water: WaterTarget): String = "${formatNumber(water.goal)} ml · ${formatNumber(water.glass)} ml glass"

    fun waterSpoken(water: WaterTarget): String =
        "Water, ${formatNumber(water.goal)} millilitres a day, ${formatNumber(water.glass)} millilitre glass"

    /** "Changes apply from today, Mon 12 Oct. Earlier days keep the goals they had." */
    fun fromToday(tracker: Tracker): String =
        "Changes apply from today, ${tracker.dates.label(tracker.today, "EEE d MMM")}. Earlier days keep the goals they had."
}

/** Which of the five rows an editor is open for: `water` or a slot's wire key. Saveable as a string. */
object GoalKey {
    const val WATER = "water"
    fun slot(key: String): TargetSlot? = TargetSlot.fromWire(key)
}

/** Setup's unsaved targets survive rotation and process death. */
val TargetsSaver: Saver<Targets, Any> = listSaver(
    save = { targets ->
        listOf<Any?>(targets.water.goal, targets.water.glass) + TargetSlot.entries.flatMap { slot ->
            val target = targets[slot]
            listOf(target.name, target.amount, target.unit?.wire, target.icon)
        }
    },
    restore = { values ->
        var targets = Targets.STANDARD.copy(water = WaterTarget(values[0] as Long, values[1] as Long))
        TargetSlot.entries.forEachIndexed { index, slot ->
            val at = 2 + index * 4
            targets = targets.with(slot, Target(values[at] as String, values[at + 1] as Long?,
                (values[at + 2] as String?)?.let(TargetUnit::fromWire), values[at + 3] as String?))
        }
        targets
    },
)

/** One of the five: icon, name, the target in force and a chevron; tapping opens its editor. */
@Composable
fun GoalRow(icon: ImageVector, title: String, detail: String, spoken: String, onClick: () -> Unit, tag: String, tint: Color = P.textPrimary) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = "$spoken. Change" }.testTag(tag),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(22.dp))
        Text(title, style = Type.rowLabel, color = P.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false).widthIn(max = 180.dp))
        Text(detail, style = Type.field, color = P.textSecondary, textAlign = TextAlign.End, maxLines = 2,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = P.textTertiary)
    }
}

/** The five rows for a set of targets, separated by hairlines. Tags are `goal-<key>`. */
@Composable
fun GoalRows(targets: Targets, onEdit: (String) -> Unit) {
    GoalRow(Icons.Filled.WaterDrop, "Water", GoalWords.water(targets.water), GoalWords.waterSpoken(targets.water),
        { onEdit(GoalKey.WATER) }, "goal-water", tint = P.water)
    for (slot in TargetSlot.entries) {
        val target = targets[slot]
        Hairline()
        GoalRow(GoalIcons.of(slot, target).vector, target.name, GoalWords.detail(slot, target), GoalWords.spoken(slot, target),
            { onEdit(slot.wire) }, "goal-${slot.wire}")
    }
}

/** A capsule choice: presets, glass sizes and repeat options. */
@Composable
fun ChoiceChip(label: String, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier, spoken: String = label) {
    Box(
        modifier.heightIn(min = 40.dp).clip(CircleShape)
            .background(if (selected) P.accentTint else P.controlFill)
            .border(1.5.dp, if (selected) P.accentText.copy(alpha = 0.6f) else Color.Transparent, CircleShape)
            .clickable(role = Role.RadioButton, onClick = onClick)
            .semantics { contentDescription = spoken; this.selected = selected }
            .padding(horizontal = 14.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = Type.badge, color = if (selected) P.accentText else P.textPrimary, maxLines = 1)
    }
}

/** − value + with a spoken value; the buttons stop at the limits. */
@Composable
fun Stepper(value: String, spoken: String, onMinus: () -> Unit, onPlus: () -> Unit, canMinus: Boolean, canPlus: Boolean,
            minusLabel: String, plusLabel: String, tag: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        RoundIconButton(Icons.Filled.Remove, minusLabel, onMinus, enabled = canMinus, size = 40.dp, modifier = Modifier.testTag("$tag-minus"))
        Text(value, style = Type.appName.copy(fontFeatureSettings = "tnum"), color = P.textPrimary, textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(min = 88.dp).semantics { contentDescription = spoken }.testTag(tag))
        RoundIconButton(Icons.Filled.Add, plusLabel, onPlus, enabled = canPlus, size = 40.dp, modifier = Modifier.testTag("$tag-plus"))
    }
}

/** An editor's title row: Cancel, the title and Done (enabled once the values are valid). */
@Composable
private fun EditorHeader(title: String, canSave: Boolean, onCancel: () -> Unit, onDone: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        TextButton(onCancel, modifier = Modifier.testTag("goal-cancel")) { Text("Cancel", style = Type.pill, color = P.accentText) }
        Text(title, style = Type.appName, color = P.textPrimary, textAlign = TextAlign.Center, maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).semantics { heading() })
        TextButton(onDone, enabled = canSave, modifier = Modifier.testTag("goal-done")) {
            Text("Done", style = Type.pill, color = if (canSave) P.accentText else P.textTertiary)
        }
    }
}

/**
 * The water editor: the daily goal in 250 ml steps from 1,000 to 5,000 ml, and the glass the +
 * button pours (50 to 1,000 ml, no more than the goal).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WaterGoalEditor(initial: WaterTarget, note: String?, error: String?, onCancel: () -> Unit, onDone: (WaterTarget) -> Unit) {
    var goal by rememberSaveable { mutableStateOf(initial.goal) }
    var glass by rememberSaveable { mutableStateOf(initial.glass) }
    var other by rememberSaveable { mutableStateOf(if (initial.glass in GoalPresets.glasses) null else initial.glass.toString()) }
    val chosen = other?.toLongOrNull() ?: if (other != null) null else glass
    val target = chosen?.let { WaterTarget(goal, it) }
    val problem = when {
        chosen == null || chosen !in WaterTarget.GLASSES -> "Enter a glass of 50 to 1,000 ml."
        chosen > goal -> "Your glass can't be more than your daily goal."
        else -> null
    }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        EditorHeader("Water", target?.isValid == true, onCancel) { target?.let(onDone) }
        GlassCard {
            Column(Modifier.padding(Size.sectionHorizontal), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Eyebrow("Daily goal")
                Stepper("${formatNumber(goal)} ml", "Daily goal, ${formatNumber(goal)} millilitres",
                    { goal = (goal - 250).coerceAtLeast(WaterTarget.GOALS.first) }, { goal = (goal + 250).coerceAtMost(WaterTarget.GOALS.last) },
                    goal > WaterTarget.GOALS.first, goal < WaterTarget.GOALS.last, "Lower the daily goal", "Raise the daily goal", "water-goal")
                Text("1,000 to 5,000 ml", style = Type.caption, color = P.textTertiary)
                Hairline()
                Eyebrow("Your glass or bottle")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    GoalPresets.glasses.forEach { size ->
                        ChoiceChip("${formatNumber(size)} ml", other == null && glass == size, { glass = size; other = null },
                            Modifier.testTag("glass-$size"), spoken = "${formatNumber(size)} millilitre glass")
                    }
                    ChoiceChip("Other…", other != null, { other = other ?: glass.toString() }, Modifier.testTag("glass-other"),
                        spoken = "Other glass size")
                }
                other?.let { text ->
                    DesignField(text, { value -> other = value.filter { it in '0'..'9' }.take(4) }, "Glass in ml", Icons.Filled.WaterDrop,
                        keyboardType = KeyboardType.Number, imeAction = ImeAction.Done, testTag = "glass-other-amount")
                }
                if (problem != null) FieldError(problem, Modifier.testTag("water-goal-error"))
                else if (chosen != null) {
                    Text("The + button adds ${formatNumber(chosen)} ml. About ${(goal + chosen - 1) / chosen} glasses a day.",
                        style = Type.caption, color = P.textSecondary, modifier = Modifier.testTag("water-goal-summary"))
                }
            }
        }
        note?.let { Text(it, style = Type.caption, color = P.textSecondary) }
        error?.let { FieldError(it) }
    }
}

/**
 * An activity, diet or reading editor: presets, then the name, an optional amount and unit, and
 * an icon (diet takes a name only). Completion stays a tick, so the amount is what it shows.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SlotGoalEditor(slot: TargetSlot, initial: Target, note: String?, error: String?, onCancel: () -> Unit, onDone: (Target) -> Unit) {
    var name by rememberSaveable { mutableStateOf(initial.name) }
    var amount by rememberSaveable { mutableStateOf(initial.amount?.toString()) }
    var unit by rememberSaveable { mutableStateOf(initial.unit?.wire) }
    var icon by rememberSaveable { mutableStateOf(initial.icon) }
    var units by rememberSaveable { mutableStateOf(false) }
    val chosenUnit = unit?.let(TargetUnit::fromWire)
    val number = amount?.toLongOrNull()
    val clean = Challenge.targetName(name)
    // The default icon stays unset unless it was set before, so choosing it again writes nothing.
    val storedIcon = if (icon == GoalIcons.default(slot) && initial.icon == null) null else icon
    val target = clean?.let { Target(it, number.takeIf { chosenUnit != null }, chosenUnit, if (slot == TargetSlot.DIET) initial.icon else storedIcon) }
    val amountProblem = if (chosenUnit != null && (number == null || number !in chosenUnit.amounts)) GoalWords.range(chosenUnit) else null
    val valid = target != null && amountProblem == null && target.isValid(slot)

    fun choose(preset: Target) {
        name = preset.name
        amount = preset.amount?.toString()
        unit = preset.unit?.wire
        icon = preset.icon
    }

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        EditorHeader(GoalWords.slotTitle(slot), valid, onCancel) { if (valid) target?.let(onDone) }
        GlassCard {
            Column(Modifier.padding(Size.sectionHorizontal), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val presets = GoalPresets.of(slot)
                    val current = Target(name.trim(), number.takeIf { chosenUnit != null }, chosenUnit, storedIcon)
                    presets.forEach { preset ->
                        ChoiceChip(preset.name, preset == current, { choose(preset) }, Modifier.testTag("preset-${preset.name}"),
                            spoken = listOfNotNull(preset.name, GoalWords.amountSpoken(preset)).joinToString(", "))
                    }
                    ChoiceChip("Custom…", presets.none { it == current }, { name = "" }, Modifier.testTag("preset-custom"),
                        spoken = "Custom name")
                }
                Hairline()
                Eyebrow("Name")
                DesignField(name, { name = it }, "Name", if (slot == TargetSlot.DIET) Icons.Outlined.Eco else Icons.AutoMirrored.Outlined.Label,
                    imeAction = ImeAction.Done, testTag = "goal-name")
                val invalidName = name.isNotEmpty() && clean == null
                Text(if (invalidName) "Use a name of 1 to 20 characters on one line." else "One line, 1 to 20 characters.",
                    style = Type.caption, color = if (invalidName) P.danger else P.textTertiary, modifier = Modifier.testTag("goal-name-help"))
                if (slot != TargetSlot.DIET) {
                    Hairline()
                    Eyebrow("Daily target")
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (chosenUnit != null) {
                            val step = GoalWords.step(chosenUnit)
                            val value = number ?: chosenUnit.amounts.first
                            Stepper(number?.let(::formatNumber) ?: "–",
                                "Daily target, ${GoalWords.amountSpoken(Target(name, value, chosenUnit)) ?: ""}",
                                { amount = (value - step).coerceIn(chosenUnit.amounts).toString() },
                                { amount = (value + step).coerceIn(chosenUnit.amounts).toString() },
                                value > chosenUnit.amounts.first, value < chosenUnit.amounts.last, "Less", "More", "goal-amount")
                        }
                        Box {
                            TintedPill(chosenUnit?.let(GoalWords::unitName) ?: "No amount", { units = true },
                                Modifier.semantics { contentDescription = "Unit, ${chosenUnit?.let(GoalWords::unitName) ?: "no amount"}" }
                                    .testTag("goal-unit"), icon = Icons.Filled.ArrowDropDown, height = 40.dp)
                            DropdownMenu(units, { units = false }) {
                                DropdownMenuItem({ Text("No amount") }, onClick = { unit = null; amount = null; units = false },
                                    trailingIcon = { if (chosenUnit == null) Icon(Icons.Filled.Check, null) })
                                TargetUnit.entries.forEach { option ->
                                    DropdownMenuItem({ Text(GoalWords.unitName(option)) }, onClick = {
                                        if (option != chosenUnit) { unit = option.wire; amount = GoalWords.suggested(option).toString() }
                                        units = false
                                    }, trailingIcon = { if (option == chosenUnit) Icon(Icons.Filled.Check, null) },
                                        modifier = Modifier.testTag("goal-unit-${option.wire}"))
                                }
                            }
                        }
                    }
                    if (chosenUnit != null) {
                        DesignField(amount ?: "", { value -> amount = value.filter { it in '0'..'9' }.take(6) }, "Amount",
                            Icons.Outlined.Straighten, keyboardType = KeyboardType.Number, imeAction = ImeAction.Done, testTag = "goal-amount-field")
                    }
                    amountProblem?.let { FieldError(it, Modifier.testTag("goal-amount-error")) }
                    Hairline()
                    Eyebrow("Icon")
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        val selectedID = GoalIcons.of(slot, Target(name, icon = icon)).id
                        GoalIcons.all.forEach { choice ->
                            val selected = choice.id == selectedID
                            Box(
                                Modifier.size(44.dp).clip(CircleShape).background(if (selected) P.accentTint else P.controlFill)
                                    .border(1.5.dp, if (selected) P.accentText.copy(alpha = 0.6f) else Color.Transparent, CircleShape)
                                    .clickable(role = Role.RadioButton) { icon = choice.id }
                                    .semantics { contentDescription = "${choice.label} icon"; this.selected = selected }
                                    .testTag("icon-${choice.id}"),
                                contentAlignment = Alignment.Center,
                            ) { Icon(choice.vector, null, tint = if (selected) P.accentText else P.textPrimary, modifier = Modifier.size(22.dp)) }
                        }
                    }
                }
                Hairline()
                // "Shows as ( o ) YOGA · 30 min": the ring label and detail Today will use.
                val preview = target ?: Target(name.ifBlank { "Name" }, number.takeIf { chosenUnit != null }, chosenUnit, storedIcon)
                val detail = GoalWords.detail(slot, preview)
                Row(Modifier.semantics(mergeDescendants = true) {
                    contentDescription = "Shows as ${GoalWords.spoken(slot, preview)}"
                }.testTag("goal-preview"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Shows as", style = Type.caption, color = P.textTertiary)
                    Icon(GoalIcons.of(slot, preview).vector, null, tint = P.textPrimary, modifier = Modifier.size(18.dp))
                    Eyebrow(preview.name, P.textPrimary, Type.ringLabel, modifier = Modifier.weight(1f, fill = false))
                    if (detail.isNotEmpty()) Text("· $detail", style = Type.caption, color = P.textSecondary, maxLines = 1)
                }
                Text(if (slot == TargetSlot.DIET) "Each day stays pending, clean or missed, by your own rules."
                    else "You tick it yourself when it's done.", style = Type.caption, color = P.textSecondary)
            }
        }
        note?.let { Text(it, style = Type.caption, color = P.textSecondary) }
        error?.let { FieldError(it) }
    }
}

/** The editor for one of the five rows, inside whatever sheet holds it. */
@Composable
fun GoalEditor(key: String, targets: Targets, note: String?, error: String?, onCancel: () -> Unit, onDone: (Targets) -> Unit) {
    val slot = GoalKey.slot(key)
    if (slot == null) WaterGoalEditor(targets.water, note, error, onCancel) { onDone(targets.copy(water = it)) }
    else SlotGoalEditor(slot, targets[slot], note, error, onCancel) { onDone(targets.with(slot, it)) }
}

/** Setup's editor, one sheet at a time. */
@Composable
fun GoalEditorSheet(key: String, targets: Targets, onDismiss: () -> Unit, onDone: (Targets) -> Unit) {
    AppSheet(onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp)) {
            GoalEditor(key, targets, null, null, onDismiss, onDone)
        }
    }
}

/**
 * Account › Daily goals: today's five, each editable. A change is recorded on today and applies
 * from today; earlier days keep theirs. Until the server has the custom goals update, the
 * change stays saved on this phone and waits, and the sheet says so.
 */
@Composable
fun DailyGoalsSheet(tracker: Tracker, initialEditing: String? = null, onDismiss: () -> Unit) {
    tracker.observe()
    var editing by rememberSaveable { mutableStateOf(initialEditing) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    val targets = tracker.todayTargets
    val note = GoalWords.fromToday(tracker)
    AppSheet(onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            val key = editing
            if (key != null) {
                GoalEditor(key, targets, note, error, { editing = null; error = null }) { changed ->
                    error = tracker.setGoals(changed)
                    if (error == null) editing = null
                }
            } else {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Daily goals", style = Type.appName, color = P.textPrimary, modifier = Modifier.weight(1f).semantics { heading() })
                    TextButton(onDismiss, modifier = Modifier.testTag("goals-done")) { Text("Done", style = Type.pill, color = P.accentText) }
                }
                GlassCard {
                    Column(Modifier.padding(horizontal = Size.sectionHorizontal, vertical = 6.dp)) {
                        GoalRows(targets) { error = null; editing = it }
                    }
                }
                Text(note, style = Type.caption, color = P.textSecondary, modifier = Modifier.testTag("goals-note"))
                if (tracker.syncError == ChallengeSyncError.SERVER_NEEDS_CUSTOM_GOALS_UPDATE.message) {
                    Row(Modifier.testTag("goals-server-update"), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Outlined.CloudOff, null, tint = P.amberText, modifier = Modifier.size(16.dp))
                        Text("The server needs an update before changed goals can sync. They're saved on this phone and apply here " +
                            "now; other devices get them once the server is updated.", style = Type.caption, color = P.amberText)
                    }
                }
                error?.let { FieldError(it) }
            }
        }
    }
}

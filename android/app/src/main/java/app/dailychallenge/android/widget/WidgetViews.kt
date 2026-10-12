package app.dailychallenge.android.widget

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.widget.RemoteViews
import androidx.annotation.ColorRes
import androidx.annotation.DrawableRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.graphics.createBitmap
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.RowScope
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.color.ColorProvider
import androidx.glance.unit.ColorProvider
import app.dailychallenge.android.MainActivity
import app.dailychallenge.android.R
import app.dailychallenge.core.DayStatus
import app.dailychallenge.core.DietState
import app.dailychallenge.core.Extra
import app.dailychallenge.core.Habit
import app.dailychallenge.core.Targets
import app.dailychallenge.core.WidgetState
import app.dailychallenge.core.WidgetTap
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// The widgets draw the app's design system (Theme.kt, docs/design-system.md): the Today jug, the
// ring gauges with their icons and state glyphs, the extras checklist and the same words. Every
// state has a glyph as well as a colour (check, dash, ×), and every control speaks its state.

/** Water: the jug and today's total toward today's goal, with + (today's glass size) and − (today's latest pour). */
class WaterWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact
    override suspend fun provideGlance(context: Context, id: GlanceId) = provideContent {
        WidgetSurface(loadState(), Destination.TODAY) { WaterContent(it) }
    }
}

/** Daily requirements: workout, walk, clean diet and Bible as Today's ring gauges, with the day and streak. */
class RequirementsWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact
    override suspend fun provideGlance(context: Context, id: GlanceId) = provideContent {
        WidgetSurface(loadState(), Destination.TODAY) { RequirementsContent(it) }
    }
}

/** Extras: today's checklist, tap to tick; the app manages them. */
class ExtrasWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact
    override suspend fun provideGlance(context: Context, id: GlanceId) = provideContent {
        WidgetSurface(loadState(), Destination.EXTRAS) { ExtrasContent(it) }
    }
}

/** Reloaded whenever [ChallengeWidgets] redraws, so a composition that is still running shows the new data. */
@Composable
private fun loadState(): WidgetState {
    val context = LocalContext.current
    val version by ChallengeWidgets.version.collectAsState()
    return remember(version) { ChallengeWidgets.load(context) }
}

enum class Destination(val key: String) { TODAY("today"), EXTRAS("extras") }

/** Opens the app on Today, or on Manage extras; sign-in and setup still come first when needed. */
fun openApp(context: Context, destination: Destination): Action = actionStartActivity(
    Intent(context, MainActivity::class.java)
        .setAction("app.dailychallenge.android.OPEN_${destination.name}")
        .putExtra(MainActivity.DESTINATION, destination.key)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
)

private fun tap(tap: WidgetTap, state: WidgetState.Ready): Action = actionRunCallback<WidgetTapCallback>(actionParametersOf(
    WidgetTapCallback.Keys.kind to tap.kind,
    WidgetTapCallback.Keys.target to tap.target,
    WidgetTapCallback.Keys.generation to state.binding.generation.toString(),
    WidgetTapCallback.Keys.challenge to state.binding.challengeID.toString(),
))

/**
 * Colours that follow Light and Dark: each resource's Light and Dark values, from which Android 12
 * and later pick on the home screen itself, so a theme change redraws without the app. Earlier
 * versions draw the colours of the moment, and the app redraws them on a theme change.
 */
private class Paint(private val context: Context) {
    private fun themed(night: Boolean): Context = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
        uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
            if (night) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
    })
    private val day by lazy { themed(night = false) }
    private val night by lazy { themed(night = true) }
    fun of(@ColorRes id: Int): ColorProvider = ColorProvider(day = Color(day.getColor(id)), night = Color(night.getColor(id)))
    fun tint(@ColorRes id: Int) = ColorFilter.tint(of(id))
    val fontScale: Float get() = context.resources.configuration.fontScale
}

@Composable
private fun paint(): Paint {
    val context = LocalContext.current
    return remember(context) { Paint(context) }
}

private object Fonts {
    val eyebrow = 10.sp
    val date = 11.sp
    val caption = 12.sp
    val row = 14.sp
    val pill = 15.sp
    val heading = 14.sp
    val total = 26.sp
    val smallTotal = 22.sp
}

@Composable
private fun Label(text: String, size: TextUnit, color: ColorProvider, weight: FontWeight = FontWeight.Medium,
                  modifier: GlanceModifier = GlanceModifier, maxLines: Int = 1) {
    Text(text, modifier, TextStyle(color = color, fontSize = size, fontWeight = weight), maxLines)
}

private val number: NumberFormat get() = NumberFormat.getIntegerInstance(Locale.getDefault())

/** The sheet every widget sits on; anything not a control opens the app. */
@Composable
internal fun WidgetSurface(state: WidgetState, destination: Destination, content: @Composable (WidgetState.Ready) -> Unit) {
    val context = LocalContext.current
    val p = paint()
    Box(
        GlanceModifier.fillMaxSize().appWidgetBackground().cornerRadius(24.dp)
            .background(ImageProvider(R.drawable.widget_shape_surface), colorFilter = p.tint(R.color.widget_surface))
            .clickable(openApp(context, destination))
            .padding(12.dp),
    ) {
        if (state is WidgetState.Ready) content(state) else StatusView(state)
    }
}

/** Signed out, no challenge, or history the widget cannot read: a calm line, never cached data. */
@Composable
private fun StatusView(state: WidgetState) {
    val p = paint()
    val size = LocalSize.current
    val compact = size.width < 200.dp
    Column(
        GlanceModifier.fillMaxSize().semantics { contentDescription = "Daily Challenge. ${state.message}" },
        verticalAlignment = if (compact) Alignment.Top else Alignment.CenterVertically,
        horizontalAlignment = if (compact) Alignment.Start else Alignment.CenterHorizontally,
    ) {
        if (compact) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AppMark(24.dp)
                Spacer(GlanceModifier.width(8.dp))
                Label("Daily Challenge", Fonts.heading, p.of(R.color.widget_text_primary), FontWeight.Bold, maxLines = 2)
            }
            Spacer(GlanceModifier.defaultWeight())
            Label(state.message, Fonts.caption, p.of(R.color.widget_text_secondary), maxLines = 3)
        } else {
            AppMark(32.dp)
            Spacer(GlanceModifier.height(6.dp))
            Label("Daily Challenge", Fonts.heading, p.of(R.color.widget_text_primary), FontWeight.Bold)
            Spacer(GlanceModifier.height(4.dp))
            Label(state.message, Fonts.row, p.of(R.color.widget_text_secondary), maxLines = 2)
        }
        Spacer(GlanceModifier.height(4.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Label("Open", Fonts.caption, p.of(R.color.widget_accent_text), FontWeight.Bold)
            Spacer(GlanceModifier.width(3.dp))
            Image(ImageProvider(R.drawable.widget_ic_open), null, GlanceModifier.size(12.dp), colorFilter = p.tint(R.color.widget_accent_text))
        }
    }
}

/** The app mark: a blue rounded tile with a white drop. */
@Composable
private fun AppMark(size: Dp) {
    val p = paint()
    Box(
        GlanceModifier.size(size).background(ImageProvider(R.drawable.widget_shape_mark), colorFilter = p.tint(R.color.widget_primary)),
        contentAlignment = Alignment.Center,
    ) {
        Image(ImageProvider(R.drawable.widget_ic_drop), null, GlanceModifier.size(size * 0.55f), colorFilter = p.tint(R.color.widget_on_primary))
    }
}

/** "12 Oct · Jersey": the day in the challenge's zone, so a phone in another zone makes sense. */
@Composable
private fun DateLabel(state: WidgetState.Ready, short: Boolean = false) {
    Label(if (short) state.dateLabel.substringBefore(" · ") else state.dateLabel, Fonts.date, paint().of(R.color.widget_text_tertiary),
        modifier = GlanceModifier.semantics { contentDescription = "Challenge day ${state.dateLabel}" })
}

@Composable
private fun Heading(title: String, state: WidgetState.Ready) {
    val p = paint()
    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Label(title.uppercase(), Fonts.eyebrow, p.of(R.color.widget_text_secondary), FontWeight.Bold)
        Spacer(GlanceModifier.width(6.dp).defaultWeight())
        DateLabel(state, short = LocalSize.current.width < 170.dp)
    }
}

// MARK: Water

/**
 * The Today jug filled to the total, clamped at full: it holds that day's goal, and past the
 * goal two drops show below it. Android 12 and later draw the drawable on the home screen
 * (colours follow the theme there); earlier versions get a picture drawn now, in the current theme.
 */
@Composable
private fun WidgetJug(millilitres: Long, goal: Long, height: Dp) {
    val context = LocalContext.current
    val width = height * (96f / 126f)
    val res = if (millilitres > goal) R.drawable.widget_jug_over else R.drawable.widget_jug
    val level = jugLevel(millilitres, goal)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val views = RemoteViews(context.packageName, R.layout.widget_jug).apply {
            setImageViewResource(R.id.widget_jug_image, res)
            setInt(R.id.widget_jug_image, "setImageLevel", level)
        }
        AndroidRemoteViews(views, GlanceModifier.size(width, height))
    } else {
        Image(ImageProvider(picture(context, res, level, DpSize(width, height))), null, GlanceModifier.size(width, height))
    }
}

/** The water clips from the bottom of the 126-high frame; the vessel spans 10 to 110 in it. */
fun jugLevel(millilitres: Long, goal: Long = Targets.STANDARD.water.goal): Int {
    val fill = (millilitres / goal.toDouble()).coerceIn(0.0, 1.0)
    return if (fill <= 0.0) 0 else ((16 + 100 * fill) / 126 * 10_000).roundToInt()
}

private fun picture(context: Context, @DrawableRes res: Int, level: Int, size: DpSize): Bitmap {
    val density = context.resources.displayMetrics.density
    val width = max(1, (size.width.value * density).roundToInt())
    val height = max(1, (size.height.value * density).roundToInt())
    val bitmap = createBitmap(width, height)
    context.getDrawable(res)!!.mutate().apply {
        setBounds(0, 0, width, height)
        this.level = level
        draw(Canvas(bitmap))
    }
    return bitmap
}

private fun waterSpoken(ml: Long, goal: Long): String = "Water, ${number.format(ml)} of ${number.format(goal)} millilitres" +
    when { ml > goal -> ", goal exceeded"; ml == goal -> ", goal met"; else -> "" }

/** "4 L", "2.5 L", "3.25 L": a goal in whole 250 ml steps as litres. */
private fun litres(goal: Long): String =
    NumberFormat.getNumberInstance(Locale.getDefault()).apply { maximumFractionDigits = 2 }.format(goal / 1_000.0) + " L"

@Composable
internal fun WaterContent(state: WidgetState.Ready) {
    if (LocalSize.current.width >= 200.dp) WaterMedium(state) else WaterSmall(state)
}

@Composable
private fun WaterSmall(state: WidgetState.Ready) {
    val p = paint()
    val size = LocalSize.current
    val ml = state.summary.waterMillilitres
    val goal = state.summary.targets.water.goal
    val inner = DpSize(size.width - 24.dp, size.height - 24.dp)
    val showHeading = inner.height >= 118.dp
    val buttons = 36.dp
    // Beside the total when the row is wide enough, above it in a tall narrow widget; the jug
    // shrinks, then steps aside, before the total is cut.
    val digits = number.format(ml).length + 0.5f
    val totalWidth = (max(digits * Fonts.smallTotal.value * 0.62f, 10 * Fonts.caption.value * 0.58f) * p.fontScale).dp + 8.dp
    val totalHeight = ((Fonts.smallTotal.value + Fonts.caption.value) * 1.35f * p.fontScale).dp
    val free = inner.height - buttons - 8.dp - if (showHeading) 28.dp else 0.dp
    val beside = min(min(96f, free.value), (inner.width - totalWidth).value / (96f / 126f))
    val above = min(min(110f, (free - totalHeight - 6.dp).value), inner.width.value / (96f / 126f))
    val stacked = beside < 48f && above > beside
    val jug = if (stacked) above else beside
    val total: @Composable () -> Unit = {
        Column(GlanceModifier.semantics { contentDescription = waterSpoken(ml, goal) }) {
            Label(number.format(ml), Fonts.smallTotal, p.of(R.color.widget_text_primary), FontWeight.Bold)
            Label("ml / ${number.format(goal)}", Fonts.caption,
                p.of(if (state.summary.waterComplete) R.color.widget_done_text else R.color.widget_text_secondary))
        }
    }
    Column(GlanceModifier.fillMaxSize()) {
        if (showHeading) {
            Heading("Water", state)
            Spacer(GlanceModifier.height(6.dp))
        }
        if (stacked) {
            Column(GlanceModifier.fillMaxWidth().defaultWeight(), verticalAlignment = Alignment.CenterVertically) {
                if (jug >= 34f) {
                    WidgetJug(ml, goal, jug.dp)
                    Spacer(GlanceModifier.height(6.dp))
                }
                total()
            }
        } else {
            Row(GlanceModifier.fillMaxWidth().defaultWeight(), verticalAlignment = Alignment.CenterVertically) {
                if (jug >= 34f) {
                    WidgetJug(ml, goal, jug.dp)
                    Spacer(GlanceModifier.width(8.dp))
                }
                total()
            }
        }
        Spacer(GlanceModifier.height(8.dp))
        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            UndoButton(state, buttons)
            Spacer(GlanceModifier.width(6.dp))
            PourPill(state, buttons, GlanceModifier.defaultWeight(), width = inner.width - buttons - 6.dp)
        }
    }
}

@Composable
private fun WaterMedium(state: WidgetState.Ready) {
    val p = paint()
    val size = LocalSize.current
    val ml = state.summary.waterMillilitres
    val goal = state.summary.targets.water.goal
    val innerHeight = size.height - 24.dp
    val goalMet = state.summary.waterComplete
    Row(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
        WidgetJug(ml, goal, min(innerHeight.value, 124f).dp)
        Spacer(GlanceModifier.width(14.dp))
        Column(GlanceModifier.defaultWeight().fillMaxSize()) {
            if (innerHeight >= 118.dp) Heading("Water", state)
            Spacer(GlanceModifier.defaultWeight())
            Column(GlanceModifier.semantics { contentDescription = waterSpoken(ml, goal) }) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Label("${number.format(ml)} ml", Fonts.total, p.of(R.color.widget_text_primary), FontWeight.Bold)
                    Spacer(GlanceModifier.width(5.dp))
                    Label("/ ${number.format(goal)}", Fonts.caption, p.of(if (goalMet) R.color.widget_done_text else R.color.widget_text_secondary),
                        modifier = GlanceModifier.padding(bottom = 4.dp))
                }
                if (innerHeight >= 100.dp) {
                    Label(if (goalMet) "Goal met · ${litres(goal)}" else "${number.format(goal - ml)} ml to go · ${litres(goal)} goal", Fonts.caption,
                        p.of(if (goalMet) R.color.widget_done_text else R.color.widget_text_secondary))
                }
            }
            Spacer(GlanceModifier.defaultWeight())
            Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                UndoButton(state, 40.dp)
                Spacer(GlanceModifier.width(10.dp))
                PourPill(state, 40.dp, GlanceModifier.defaultWeight())
            }
        }
    }
}

/**
 * + today's glass size (450 ml unless changed): the primary pill until the goal is met, then the
 * quieter tinted one (as in Today). The tap pours the glass size stored for the tap's day.
 */
@Composable
private fun PourPill(state: WidgetState.Ready, height: Dp, modifier: GlanceModifier, width: Dp = Dp.Infinity) {
    val p = paint()
    val glass = number.format(state.summary.targets.water.glass)
    // Narrow widgets and large text: a smaller label, then the number alone (it still speaks "Add 450 ml").
    // "450 ml" in bold is about half an em per character, plus the icon, its gap and some air.
    fun fits(size: TextUnit, icon: Float) = (glass.length + 3) * 0.52f * size.value * p.fontScale + icon + 8 <= width.value
    val compact = !fits(Fonts.pill, icon = 20f)
    val label = if (fits(13.sp, icon = 15f)) "$glass ml" else glass
    val quiet = state.summary.waterComplete
    val foreground = if (quiet) R.color.widget_text_primary else R.color.widget_on_primary
    Row(
        modifier.height(height)
            .background(ImageProvider(R.drawable.widget_shape_capsule), colorFilter = p.tint(if (quiet) R.color.widget_control_fill else R.color.widget_primary))
            .clickable(tap(WidgetTap.Pour, state))
            .semantics { contentDescription = "Add $glass ml" },
        horizontalAlignment = Alignment.CenterHorizontally, verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(ImageProvider(R.drawable.widget_ic_add), null, GlanceModifier.size(if (compact) 13.dp else 16.dp), colorFilter = p.tint(foreground))
        Spacer(GlanceModifier.width(if (compact) 2.dp else 4.dp))
        Label(label, if (compact) 13.sp else Fonts.pill, p.of(foreground), FontWeight.Bold)
    }
}

/** − undoes today's latest active pour; with none it is drawn disabled and records nothing. */
@Composable
private fun UndoButton(state: WidgetState.Ready, size: Dp) {
    val p = paint()
    val canUndo = state.summary.activePours.isNotEmpty()
    val modifier = GlanceModifier.size(size)
        .background(ImageProvider(R.drawable.widget_shape_circle), colorFilter = p.tint(R.color.widget_control_fill))
        .semantics { contentDescription = if (canUndo) "Undo latest pour" else "Undo latest pour, no pour today" }
    Box(if (canUndo) modifier.clickable(tap(WidgetTap.UndoPour, state)) else modifier, contentAlignment = Alignment.Center) {
        Image(ImageProvider(R.drawable.widget_ic_remove), null, GlanceModifier.size(size * 0.45f),
            colorFilter = p.tint(if (canUndo) R.color.widget_text_primary else R.color.widget_text_tertiary))
    }
}

// MARK: Daily requirements

private enum class Ring { PENDING, DONE, MISSED }

@Composable
internal fun RequirementsContent(state: WidgetState.Ready) {
    val p = paint()
    val size = LocalSize.current
    val inner = DpSize(size.width - 24.dp, size.height - 24.dp)
    val label = (14f * p.fontScale).dp
    val ring = min(64f, min(inner.width.value / 4 - 10, (inner.height - 26.dp - 6.dp - label).value)).coerceAtLeast(34f).dp
    val summary = state.summary
    Column(GlanceModifier.fillMaxSize()) {
        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            DayBadge(state)
            Spacer(GlanceModifier.width(8.dp))
            Streak(state)
            Spacer(GlanceModifier.defaultWeight())
            if (inner.width >= 240.dp) DateLabel(state)
        }
        Spacer(GlanceModifier.defaultWeight())
        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            HabitRing(state, Habit.WORKOUT, "Workout", "45 min, home or gym", R.drawable.widget_ic_workout, ring)
            HabitRing(state, Habit.WALK, "Walk", "45 minutes", R.drawable.widget_ic_walk, ring)
            // A missed diet is never changed from the widget; its ring opens the app instead.
            val diet = summary.diet
            val dietAction = if (diet == DietState.MISSED) openApp(LocalContext.current, Destination.TODAY) else tap(WidgetTap.ToggleDiet, state)
            RingColumn(R.drawable.widget_ic_diet, "Diet",
                when (diet) { DietState.CLEAN -> Ring.DONE; DietState.MISSED -> Ring.MISSED; DietState.PENDING -> Ring.PENDING },
                ring, dietAction,
                when (diet) {
                    DietState.MISSED -> "Clean diet, missed. Opens Daily Challenge to change it"
                    DietState.CLEAN -> "Clean diet, your own rules, done"
                    DietState.PENDING -> "Clean diet, your own rules, pending"
                })
            HabitRing(state, Habit.BIBLE_READING, "Bible", "10 pages", R.drawable.widget_ic_bible, ring)
        }
        Spacer(GlanceModifier.defaultWeight())
    }
}

@Composable
private fun RowScope.HabitRing(state: WidgetState.Ready, habit: Habit, title: String, detail: String, @DrawableRes icon: Int, ring: Dp) {
    val done = habit in state.summary.completedHabits
    RingColumn(icon, title, if (done) Ring.DONE else Ring.PENDING, ring, tap(WidgetTap.ToggleHabit(habit), state),
        "$title, $detail, ${if (done) "done" else "pending"}")
}

/** Today's ring gauge: icon over a dash, check or ×; green when done, dashed red when missed. */
@Composable
private fun RowScope.RingColumn(@DrawableRes icon: Int, title: String, ring: Ring, size: Dp, action: Action, spoken: String) {
    val p = paint()
    Column(
        GlanceModifier.defaultWeight().clickable(action).semantics { contentDescription = spoken },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(GlanceModifier.size(size), contentAlignment = Alignment.Center) {
            Image(ImageProvider(if (ring == Ring.MISSED) R.drawable.widget_ring_dashed else R.drawable.widget_ring), null,
                GlanceModifier.fillMaxSize(),
                colorFilter = p.tint(when (ring) { Ring.DONE -> R.color.widget_done; Ring.MISSED -> R.color.widget_danger; Ring.PENDING -> R.color.widget_ring_track }))
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Image(ImageProvider(icon), null, GlanceModifier.size(size * 0.31f),
                    colorFilter = p.tint(when (ring) { Ring.PENDING -> R.color.widget_text_tertiary; Ring.MISSED -> R.color.widget_danger; Ring.DONE -> R.color.widget_text_primary }))
                Spacer(GlanceModifier.height(2.dp))
                when (ring) {
                    Ring.DONE -> Image(ImageProvider(R.drawable.widget_ic_check), null, GlanceModifier.size(12.dp), colorFilter = p.tint(R.color.widget_done))
                    Ring.MISSED -> Image(ImageProvider(R.drawable.widget_ic_close), null, GlanceModifier.size(12.dp), colorFilter = p.tint(R.color.widget_danger))
                    Ring.PENDING -> Box(GlanceModifier.size(12.dp), contentAlignment = Alignment.Center) {
                        Box(GlanceModifier.size(12.dp, 4.dp).background(ImageProvider(R.drawable.widget_shape_capsule), colorFilter = p.tint(R.color.widget_text_tertiary))) {}
                    }
                }
            }
        }
        Spacer(GlanceModifier.height(6.dp))
        Label(title.uppercase(), Fonts.eyebrow,
            p.of(when (ring) { Ring.PENDING -> R.color.widget_text_tertiary; Ring.MISSED -> R.color.widget_danger; Ring.DONE -> R.color.widget_text_secondary }),
            FontWeight.Bold)
    }
}

/** "Day 12", green with a check once all five are complete (as in Today). */
@Composable
private fun DayBadge(state: WidgetState.Ready) {
    val p = paint()
    val complete = state.summary.status == DayStatus.COMPLETE
    val text = state.dayNumber?.let { "Day $it" } ?: "Starts soon"
    val foreground = if (complete) R.color.widget_done_text else R.color.widget_day_badge_text
    Row(
        GlanceModifier.height(24.dp)
            .background(ImageProvider(R.drawable.widget_shape_capsule), colorFilter = p.tint(if (complete) R.color.widget_done_tint else R.color.widget_day_badge_fill))
            .padding(horizontal = 9.dp)
            .semantics { contentDescription = state.dayNumber?.let { "Day $it of 75" + if (complete) ", all five complete" else "" } ?: "Challenge starts soon" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (complete) {
            Image(ImageProvider(R.drawable.widget_ic_check), null, GlanceModifier.size(12.dp), colorFilter = p.tint(foreground))
            Spacer(GlanceModifier.width(3.dp))
        }
        Label(text, Fonts.caption, p.of(foreground), FontWeight.Bold)
    }
}

@Composable
private fun Streak(state: WidgetState.Ready) {
    val p = paint()
    Row(GlanceModifier.semantics { contentDescription = "Current streak: ${state.streak} days" }, verticalAlignment = Alignment.CenterVertically) {
        Image(ImageProvider(R.drawable.widget_ic_flame), null, GlanceModifier.size(16.dp), colorFilter = p.tint(R.color.widget_amber))
        Spacer(GlanceModifier.width(3.dp))
        Label("${state.streak}", Fonts.caption, p.of(R.color.widget_amber_text), FontWeight.Bold)
        Spacer(GlanceModifier.width(3.dp))
        Label("/ 75", Fonts.date, p.of(R.color.widget_text_secondary))
    }
}

// MARK: Extras

/**
 * How many rows fit: no scrolling in a widget. Rows grow with the font size, so larger text shows
 * fewer rows and the "Open all" link stays.
 */
fun visibleExtraRows(count: Int, available: Dp, row: Dp, link: Dp): Int {
    if (count * row.value <= available.value) return count
    return max(0, floor((available - link).value / row.value).toInt())
}

@Composable
internal fun ExtrasContent(state: WidgetState.Ready) {
    val p = paint()
    val context = LocalContext.current
    val size = LocalSize.current
    val summary = state.summary
    val extras = summary.extras
    val row = max(36f, 24f * p.fontScale + 12f).dp
    val link = (18f * p.fontScale + 6f).dp
    val limit = visibleExtraRows(extras.size, size.height - 24.dp - (22f * p.fontScale).dp - 4.dp, row, link)
    Column(GlanceModifier.fillMaxSize()) {
        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Image(ImageProvider(R.drawable.widget_ic_checklist), null, GlanceModifier.size(18.dp), colorFilter = p.tint(R.color.widget_text_secondary))
            Spacer(GlanceModifier.width(6.dp))
            Label(if (extras.isEmpty()) "Extras" else "Extras · ${summary.extrasDone}/${extras.size}", Fonts.heading,
                p.of(R.color.widget_text_secondary), FontWeight.Bold,
                GlanceModifier.semantics {
                    contentDescription = if (extras.isEmpty()) "Extras" else "Extras, ${summary.extrasDone} of ${extras.size} done"
                })
            Spacer(GlanceModifier.defaultWeight())
            DateLabel(state)
        }
        Spacer(GlanceModifier.height(4.dp))
        if (extras.isEmpty()) {
            Column(GlanceModifier.fillMaxWidth().defaultWeight(), verticalAlignment = Alignment.CenterVertically) {
                Label("Add your own to-dos", Fonts.row, p.of(R.color.widget_text_primary))
                Spacer(GlanceModifier.height(4.dp))
                Label("Optional daily ticks that never affect the five or your streak.", Fonts.caption,
                    p.of(R.color.widget_text_secondary), maxLines = 3)
            }
        } else {
            // A nested column: Glance draws at most ten children in one.
            Column(GlanceModifier.fillMaxWidth()) {
                extras.take(limit).forEach { extra ->
                    ExtraRow(state, extra, extra.id in summary.completedExtras, summary.isLate(extra), row)
                }
            }
            Spacer(GlanceModifier.defaultWeight())
            if (extras.size > limit) {
                Row(
                    GlanceModifier.fillMaxWidth().height(link).clickable(openApp(context, Destination.EXTRAS))
                        .semantics { contentDescription = "Open all ${extras.size} extras" },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Label("Open all ${extras.size} extras", Fonts.caption, p.of(R.color.widget_accent_text), FontWeight.Bold)
                    Image(ImageProvider(R.drawable.widget_ic_chevron), null, GlanceModifier.size(14.dp), colorFilter = p.tint(R.color.widget_accent_text))
                }
            }
        }
    }
}

/** The app's checklist row: a green check or an empty circle, the title dimmed when done, "Late" once carried over. */
@Composable
private fun ExtraRow(state: WidgetState.Ready, extra: Extra, done: Boolean, late: Boolean, height: Dp) {
    val p = paint()
    Row(
        GlanceModifier.fillMaxWidth().height(height).clickable(tap(WidgetTap.ToggleExtra(extra.id), state))
            .semantics { contentDescription = extra.title + (if (late) ", late" else "") + if (done) ", done" else ", pending" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(ImageProvider(if (done) R.drawable.widget_ic_check_circle else R.drawable.widget_ic_circle), null, GlanceModifier.size(22.dp),
            colorFilter = p.tint(if (done) R.color.widget_done else R.color.widget_text_tertiary))
        Spacer(GlanceModifier.width(10.dp))
        Label(extra.title, Fonts.row, p.of(if (done) R.color.widget_text_secondary else R.color.widget_text_primary),
            modifier = GlanceModifier.defaultWeight())
        if (late) {
            Spacer(GlanceModifier.width(6.dp))
            Label("Late", Fonts.caption, p.of(R.color.widget_amber_text), FontWeight.Bold)
        }
    }
}

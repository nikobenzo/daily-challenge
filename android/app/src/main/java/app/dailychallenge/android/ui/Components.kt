package app.dailychallenge.android.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import app.dailychallenge.core.AuthModel
import app.dailychallenge.core.SyncState
import app.dailychallenge.core.Tracker
import kotlinx.coroutines.launch
import android.text.format.DateFormat as AndroidDateFormat

/**
 * Subscribes the calling composable to the tracker's changes. Every composable that reads the
 * tracker calls this itself: with strong skipping, a child given the same instance would
 * otherwise skip its parent's recomposition and keep showing old values.
 */
@Composable
fun Tracker.observe(): Long = changes.collectAsState().value

@Composable
fun AuthModel.observe(): Long = changes.collectAsState().value

/** "15:00" or "3:00 PM", following the phone's 24-hour setting, in the challenge's zone. */
@Composable
fun timeLabel(tracker: Tracker, instant: Double): String {
    val context = LocalContext.current
    return tracker.dates.label(instant, if (AndroidDateFormat.is24HourFormat(context)) "HH:mm" else "h:mm a")
}

@Composable
fun Hairline(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(1.dp).background(P.hairline))
}

/** The backdrop the glass sits on: the iPhone's gradient with a soft glow top right. */
@Composable
fun Backdrop(modifier: Modifier = Modifier) {
    val palette = P
    Canvas(modifier) {
        drawRect(Brush.verticalGradient(listOf(palette.backdropTop, palette.backdropBottom)))
        drawRect(Brush.radialGradient(listOf(palette.backdropGlow, Color.Transparent), center = Offset(size.width, 0f),
            radius = 420.dp.toPx()))
    }
}

/**
 * The glass sheet: rounded 28, translucent tint, 1 dp border with a top highlight and the
 * boards' soft shadow. Sections inside are separated by hairlines, never boxed.
 */
@Composable
fun GlassCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(Size.sheetRadius)
    val palette = P
    Column(
        modifier
            .fillMaxWidth()
            .shadow(18.dp, shape, ambientColor = palette.sheetShadow, spotColor = palette.sheetShadow)
            .clip(shape)
            .background(palette.solidGlass.copy(alpha = if (palette.dark) 0.78f else 0.86f))
            .background(palette.glass)
            .border(1.dp, Brush.verticalGradient(0f to palette.glassHighlight, 0.12f to palette.glassBorder, 1f to palette.glassBorder), shape),
        content = content,
    )
}

/** A screen: backdrop and scrolling content with the standard margins. */
@Composable
fun PhoneScreen(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Box(modifier.fillMaxSize()) {
        Backdrop(Modifier.fillMaxSize())
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().navigationBarsPadding().imePadding()
                .padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            content = content,
        )
    }
}

/** App mark, title and a trailing slot: the phone version of the popup header. */
@Composable
fun PhoneHeader(title: String = "Daily Challenge", trailing: @Composable RowScope.() -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        AppMark(30.dp)
        Text(title, style = Type.screenTitle, color = P.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).semantics { heading() })
        trailing()
    }
}

/** The blue gradient tile with a white drop. */
@Composable
fun AppMark(size: Dp = 26.dp) {
    Box(
        Modifier.size(size).shadow(4.dp, RoundedCornerShape(size * 0.27f), spotColor = P.primaryShadow)
            .clip(RoundedCornerShape(size * 0.27f)).background(P.appMarkGradient),
        contentAlignment = Alignment.Center,
    ) { Icon(Icons.Filled.WaterDrop, null, tint = Color.White, modifier = Modifier.size(size * 0.55f)) }
}

/** The round gradient hero on auth and notice screens. */
@Composable
fun HeroIcon(icon: ImageVector) {
    Box(Modifier.size(60.dp).shadow(12.dp, CircleShape, spotColor = P.primaryShadow).clip(CircleShape).background(P.primaryGradient),
        contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(28.dp))
    }
}

/** A small tinted capsule: Day 12, Today, best streak. */
@Composable
fun Badge(text: String? = null, icon: ImageVector? = null, fill: Color = P.controlFill, foreground: Color = P.textPrimary,
          height: Dp = 24.dp, iconColor: Color? = null, modifier: Modifier = Modifier) {
    Row(
        modifier.heightIn(min = height).widthIn(min = height).clip(CircleShape).background(fill)
            .padding(horizontal = if (text == null) 0.dp else 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterHorizontally),
    ) {
        icon?.let { Icon(it, null, tint = iconColor ?: foreground, modifier = Modifier.size(13.dp)) }
        text?.let { Text(it, style = Type.badge, color = foreground, maxLines = 1) }
    }
}

@Composable
private fun pressedAlpha(source: MutableInteractionSource, enabled: Boolean, pressed: Float = 0.75f, disabled: Float = 0.4f): Float {
    val isPressed by source.collectIsPressedAsState()
    return if (!enabled) disabled else if (isPressed) pressed else 1f
}

/** Primary call to action: blue gradient pill with a coloured shadow. */
@Composable
fun PrimaryPill(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: ImageVector? = null, enabled: Boolean = true,
                height: Dp = Size.pill, style: TextStyle = Type.pill, busy: Boolean = false, expands: Boolean = true) {
    val source = remember { MutableInteractionSource() }
    val shape = CircleShape
    Row(
        modifier.then(if (expands) Modifier.fillMaxWidth() else Modifier).height(height)
            .alpha(pressedAlpha(source, enabled))
            .shadow(if (enabled) 8.dp else 0.dp, shape, spotColor = P.primaryShadow, ambientColor = P.primaryShadow)
            .clip(shape).background(P.primaryGradient).border(1.dp, Color.White.copy(alpha = 0.18f), shape)
            .clickable(source, null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
    ) {
        if (busy) CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
        else icon?.let { Icon(it, null, tint = Color.White, modifier = Modifier.size(20.dp)) }
        Text(text, style = style, color = Color.White, maxLines = 1)
    }
}

/** Translucent tinted pill on the glass. */
@Composable
fun TintedPill(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: ImageVector? = null, enabled: Boolean = true,
               height: Dp = Size.pill, fill: Color = P.controlFill, foreground: Color = P.textPrimary, expands: Boolean = false,
               busy: Boolean = false) {
    val source = remember { MutableInteractionSource() }
    Row(
        modifier.then(if (expands) Modifier.fillMaxWidth() else Modifier).height(height)
            .alpha(pressedAlpha(source, enabled, 0.7f, 0.45f)).clip(CircleShape).background(fill)
            .clickable(source, null, enabled = enabled, role = Role.Button, onClick = onClick).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
    ) {
        if (busy) CircularProgressIndicator(color = foreground, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
        else icon?.let { Icon(it, null, tint = foreground, modifier = Modifier.size(18.dp)) }
        Text(text, style = Type.pill, color = foreground, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** A round icon-only control. Callers pass the spoken label. */
@Composable
fun RoundIconButton(icon: ImageVector, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                    size: Dp = Size.pill, fill: Color = P.controlFill, foreground: Color = P.textPrimary, border: Color = Color.Transparent) {
    val source = remember { MutableInteractionSource() }
    Box(
        modifier.size(size).alpha(pressedAlpha(source, enabled)).clip(CircleShape).background(fill).border(1.5.dp, border, CircleShape)
            .clickable(source, null, enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = foreground, modifier = Modifier.size(size * 0.46f)) }
}

/** A text link in the accent colour. */
@Composable
fun LinkButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: ImageVector? = null, color: Color = P.accentText) {
    val source = remember { MutableInteractionSource() }
    Row(modifier.heightIn(min = 44.dp).alpha(pressedAlpha(source, true, 0.6f)).clickable(source, null, role = Role.Button, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        icon?.let { Icon(it, null, tint = color, modifier = Modifier.size(16.dp)) }
        Text(text, style = Type.link, color = color)
    }
}

/** A settings row: fixed icon column, label, trailing content. */
@Composable
fun SettingRow(icon: ImageVector, title: String, modifier: Modifier = Modifier, tint: Color = P.textPrimary,
               trailing: @Composable RowScope.() -> Unit = {}) {
    Row(modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(22.dp))
        Text(title, style = Type.rowLabel, color = tint, maxLines = 1, modifier = Modifier.weight(1f))
        trailing()
    }
}

/** Small caps with tracking: ring labels and section eyebrows. */
@Composable
fun Eyebrow(text: String, color: Color = P.textSecondary, style: TextStyle = Type.eyebrow, modifier: Modifier = Modifier) {
    Text(text.uppercase(), style = style, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = modifier)
}

/** "Late" beside a carried-over extra: small amber text, never a pill. */
@Composable
fun LateMarker() {
    Text("Late", style = Type.caption, color = P.amberText, maxLines = 1)
}

/** Error text below a field, in the danger colour with an exclamation icon. */
@Composable
fun FieldError(text: String, modifier: Modifier = Modifier) {
    Row(modifier.semantics(mergeDescendants = true) { contentDescription = "Error: $text" }, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(Icons.Outlined.ErrorOutline, null, tint = P.danger, modifier = Modifier.size(15.dp).padding(top = 1.dp))
        Text(text, style = TextStyle(fontSize = 12.sp, fontWeight = Type.caption.fontWeight), color = P.danger)
    }
}

sealed interface RingState {
    data object Pending : RingState
    data class Progress(val value: Double) : RingState
    data object Done : RingState
    data object Missed : RingState
}

/**
 * 64 dp ring, stroke 6. Every state has a glyph, not only a colour: pending shows a dash,
 * progress a percentage, done a check, missed a dashed red ring with ×. Done pops once.
 */
@Composable
fun RingGauge(icon: ImageVector, label: String, state: RingState, showsPercent: Boolean = false, modifier: Modifier = Modifier) {
    val palette = P
    val progress by animateFloatAsState(
        when (state) { is RingState.Progress -> state.value.coerceIn(0.0, 1.0).toFloat(); RingState.Done -> 1f; else -> 0f },
        tween(350), label = "ring")
    val color by animateColorAsState(if (state == RingState.Done) palette.done else palette.water, tween(350), label = "ringColor")
    val pop = remember { Animatable(1f) }
    var previous by remember { mutableStateOf(state) }
    LaunchedEffect(state) {
        if (state == RingState.Done && previous != RingState.Done) {
            pop.animateTo(1.06f, spring(dampingRatio = 0.5f, stiffness = Spring.StiffnessMedium))
            pop.animateTo(1f, spring(dampingRatio = 0.7f))
        }
        previous = state
    }
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(Size.ring).scale(pop.value), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize().padding(Size.ringStroke / 2)) {
                val stroke = Size.ringStroke.toPx()
                if (state == RingState.Missed) {
                    drawCircle(palette.dangerRing, style = Stroke(stroke, cap = StrokeCap.Round,
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 6.dp.toPx()))))
                } else {
                    drawCircle(palette.ringTrack, style = Stroke(stroke))
                    if (progress > 0f) drawArc(color, -90f, 360f * maxOf(0.001f, progress), false, style = Stroke(stroke, cap = StrokeCap.Round))
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                val iconColor = when (state) { RingState.Pending -> palette.textTertiary; RingState.Missed -> palette.dangerRing; else -> palette.textPrimary }
                Icon(icon, null, tint = iconColor, modifier = Modifier.size(20.dp))
                when {
                    state == RingState.Done -> Icon(Icons.Filled.Check, null, tint = palette.done, modifier = Modifier.size(12.dp))
                    state == RingState.Missed -> Icon(Icons.Filled.Close, null, tint = palette.dangerRing, modifier = Modifier.size(12.dp))
                    state is RingState.Progress && showsPercent ->
                        Text("${(state.value.coerceAtMost(1.0) * 100).toInt()}%", style = TextStyle(fontSize = 10.sp, fontWeight = Type.badge.fontWeight), color = palette.textPrimary)
                    state == RingState.Pending && showsPercent ->
                        Text("0%", style = TextStyle(fontSize = 10.sp, fontWeight = Type.badge.fontWeight), color = palette.textTertiary)
                    else -> Box(Modifier.padding(vertical = 4.dp).size(12.dp, 4.dp).clip(CircleShape).background(palette.textTertiary.copy(alpha = 0.7f)))
                }
            }
        }
        val labelColor = when (state) { RingState.Pending -> palette.textTertiary; RingState.Missed -> palette.danger; else -> palette.textSecondary }
        // A chosen name longer than the standard ones scales down, then truncates; TalkBack reads it in full.
        val labelStyle = if (label.length > 8) Type.ringLabel.copy(fontSize = 8.sp, letterSpacing = 0.02.em) else Type.ringLabel
        Eyebrow(label, labelColor, labelStyle, Modifier.padding(horizontal = 2.dp))
    }
}

/** A centred icon, title, detail and actions: unavailable, checking and configuration states. */
@Composable
fun NoticeCard(icon: ImageVector, title: String, detail: String, actions: @Composable ColumnScope.() -> Unit = {}) {
    GlassCard {
        Column(Modifier.fillMaxWidth().padding(horizontal = Size.sectionHorizontal, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            HeroIcon(icon)
            Text(title, style = Type.rowLabel, color = P.textPrimary, textAlign = TextAlign.Center, modifier = Modifier.semantics { heading() })
            Text(detail, style = Type.caption, color = P.textSecondary, textAlign = TextAlign.Center)
            actions()
        }
    }
}

/** The tracker's last error under the content, dismissible. */
@Composable
fun ErrorBanner(tracker: Tracker) {
    tracker.observe()
    val error = tracker.errorMessage ?: return
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(P.dangerTint).padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
        Icon(Icons.Outlined.ErrorOutline, null, tint = P.danger, modifier = Modifier.size(18.dp))
        Text(error, style = Type.caption, color = P.danger, modifier = Modifier.weight(1f))
        RoundIconButton(Icons.Filled.Close, "Dismiss error", tracker::dismissError, size = 30.dp)
    }
}

/** The sync glyphs and short words, as on the Mac and iPhone. */
object SyncWords {
    fun icon(state: SyncState): ImageVector = when (state) {
        is SyncState.Synced -> if (state.clockWarning) Icons.Filled.Schedule else Icons.Filled.CloudDone
        is SyncState.Checking, is SyncState.SavedLocally -> Icons.Filled.CloudUpload
        SyncState.AwaitingCheck -> Icons.Filled.Cloud
        is SyncState.Unavailable -> Icons.Filled.CloudSync
        SyncState.LocalOnly -> Icons.Filled.CloudOff
    }

    fun shortText(state: SyncState, time: (Double) -> String): String = when (state) {
        is SyncState.Synced -> time(state.at)
        is SyncState.Checking -> "Syncing"
        is SyncState.SavedLocally -> "${state.pending} pending"
        SyncState.AwaitingCheck -> "Checking"
        is SyncState.Unavailable -> "Retry"
        SyncState.LocalOnly -> "Local only"
    }

    @Composable
    fun tint(state: SyncState): Color = when (state) {
        is SyncState.Synced -> if (state.clockWarning) P.amber else P.done
        is SyncState.Unavailable -> P.amber
        is SyncState.Checking, is SyncState.SavedLocally, SyncState.AwaitingCheck -> P.accentText
        SyncState.LocalOnly -> P.textTertiary
    }

    @Composable
    fun textTint(state: SyncState): Color = when (state) {
        is SyncState.Unavailable -> P.amberText
        SyncState.LocalOnly -> P.textTertiary
        else -> P.textSecondary
    }
}

/** The sync state as a chip: glyph and a short word or time; tapping syncs now. */
@Composable
fun SyncChip(tracker: Tracker) {
    tracker.observe()
    val scope = rememberCoroutineScope()
    val state = tracker.syncState
    val time = { at: Double -> tracker.dates.label(at, "HH:mm") }
    val spoken = state.plainText(app.dailychallenge.core.DeviceWording.android) { timeLabelPlain(tracker, it) }
    Row(
        Modifier.heightIn(min = 32.dp).clip(CircleShape).background(P.controlFill)
            .clickable(role = Role.Button) { if (tracker.syncActive && !tracker.isSyncing) scope.launch { tracker.sync(force = true) } }
            .semantics(mergeDescendants = true) { contentDescription = spoken }
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(SyncWords.icon(state), null, tint = SyncWords.tint(state), modifier = Modifier.size(16.dp))
        Text(SyncWords.shortText(state, time), style = Type.badge, color = SyncWords.textTint(state), maxLines = 1)
    }
}

fun timeLabelPlain(tracker: Tracker, instant: Double) = tracker.dates.label(instant, "HH:mm")

/**
 * The design's text field: a 46 dp capsule with a leading icon, focus ring and halo, and a
 * show/hide control for passwords.
 */
@Composable
fun DesignField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    secure: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    imeAction: ImeAction = ImeAction.Next,
    onSubmit: () -> Unit = {},
    monospaced: Boolean = false,
    enabled: Boolean = true,
    testTag: String? = null,
) {
    val source = remember { MutableInteractionSource() }
    val focused by source.collectIsFocusedAsState()
    var reveal by rememberSaveable { mutableStateOf(false) }
    val palette = P
    val shape = CircleShape
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        enabled = enabled,
        singleLine = true,
        textStyle = Type.field.copy(color = palette.textPrimary, fontFamily = if (monospaced) FontFamily.Monospace else FontFamily.Default),
        cursorBrush = SolidColor(palette.focus),
        interactionSource = source,
        visualTransformation = if (secure && !reveal) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = if (secure) KeyboardType.Password else keyboardType, imeAction = imeAction,
            autoCorrectEnabled = false),
        keyboardActions = KeyboardActions(onAny = { onSubmit() }),
        modifier = modifier.fillMaxWidth().then(if (testTag != null) Modifier.testTag(testTag) else Modifier)
            .semantics { contentDescription = placeholder },
        decorationBox = { inner ->
            Row(
                Modifier.heightIn(min = Size.field)
                    .then(if (focused) Modifier.border(6.dp, palette.focusHalo, shape) else Modifier)
                    .clip(shape).background(palette.fieldFill)
                    .border(if (focused) 1.5.dp else 1.dp, if (focused) palette.focus else palette.controlFill, shape)
                    .padding(start = 16.dp, end = if (secure) 4.dp else 16.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(icon, null, tint = if (focused) palette.focus else palette.textSecondary, modifier = Modifier.size(20.dp))
                Box(Modifier.weight(1f)) {
                    if (value.isEmpty()) Text(placeholder, style = Type.field, color = palette.textTertiary, maxLines = 1)
                    inner()
                }
                if (secure) {
                    Box(Modifier.size(44.dp).clip(CircleShape).clickable(role = Role.Button) { reveal = !reveal }
                        .semantics { contentDescription = if (reveal) "Hide password" else "Show password" },
                        contentAlignment = Alignment.Center) {
                        Icon(if (reveal) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility, null, tint = palette.textSecondary,
                            modifier = Modifier.size(20.dp))
                    }
                }
            }
        },
    )
}

/** System / Light / Dark as one capsule track with a lifted selected cell. */
@Composable
fun <T> Segmented(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().height(40.dp).clip(CircleShape).background(P.controlFill).padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        options.forEach { (value, label) ->
            val chosen = value == selected
            Box(
                Modifier.weight(1f).fillMaxSize().clip(CircleShape)
                    .background(if (chosen) P.segmentSelected else Color.Transparent)
                    .clickable(role = Role.RadioButton) { onSelect(value) }
                    .semantics { contentDescription = if (chosen) "$label, selected" else label },
                contentAlignment = Alignment.Center,
            ) { Text(label, style = Type.badge, color = if (chosen) P.textPrimary else P.textSecondary) }
        }
    }
}

/** A tick circle for extras rows. */
@Composable
fun TickCircle(done: Boolean) {
    if (done) Icon(Icons.Filled.CheckCircle, null, tint = P.done, modifier = Modifier.size(26.dp))
    else Box(Modifier.size(26.dp).padding(2.dp).border(2.dp, P.textTertiary, CircleShape))
}

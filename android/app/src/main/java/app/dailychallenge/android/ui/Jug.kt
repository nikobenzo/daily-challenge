package app.dailychallenge.android.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size as GeometrySize
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.dailychallenge.core.CelebrationEvent
import app.dailychallenge.core.CompletionCelebration
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** Whether the person asked Android to remove animations (Settings > Accessibility). */
@Composable
fun reduceMotion(): Boolean {
    val context = LocalContext.current
    return android.provider.Settings.Global.getFloat(context.contentResolver,
        android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
}

/**
 * The water jug, drawn as on the Mac and iPhone (`JugDrawing.swift`): 88 by 112 within a
 * 96 by 126 frame. It holds the day's goal (4,000 ml unless changed): a pour fills it with a
 * short slosh, and past the goal two drops sit below it.
 */
@Composable
fun WaterJug(millilitres: Long, goal: Long, modifier: Modifier = Modifier) {
    val palette = P
    val target = (millilitres / goal.toDouble()).coerceIn(0.0, 1.0).toFloat()
    val level = remember { Animatable(target) }
    val slosh = remember { Animatable(0f) }
    var spill by remember { mutableStateOf(0f) }
    val still = reduceMotion()
    var previous by remember { mutableStateOf(millilitres) }
    LaunchedEffect(millilitres, goal) {
        val overflowing = previous >= goal && millilitres > previous
        previous = millilitres
        if (still) { level.snapTo(target); return@LaunchedEffect }
        if (overflowing) {
            spill = 1f
            val start = System.nanoTime()
            while (spill > 0f) { spill = (1f - (System.nanoTime() - start) / 700_000_000f).coerceAtLeast(0f); delay(16) }
            return@LaunchedEffect
        }
        slosh.snapTo(1f)
        coroutineScope {
            launch { level.animateTo(target, tween(650)) }
            launch { slosh.animateTo(0f, tween(900, easing = LinearEasing)) }
        }
    }
    val description = "Water jug, $millilitres of ${formatNumber(goal)} millilitres" + if (millilitres > goal) ", goal exceeded" else ""
    Box(modifier.size(96.dp, 126.dp).semantics { contentDescription = description }) {
        Canvas(Modifier.fillMaxSize()) {
            val u = 1.dp.toPx()
            val outline = palette.jugOutline
            // Handle
            drawRoundRect(outline.copy(alpha = 0.75f), topLeft = Offset(58.5f * u, 44.5f * u), size = GeometrySize(25f * u, 39f * u),
                cornerRadius = CornerRadius(8.5f * u), style = Stroke(5f * u))
            translate(0f, 10f * u) {
                val w = 66f * u
                val h = 100f * u
                val vessel = Path().apply {
                    moveTo(w * 0.33f, 0f); lineTo(w * 0.67f, 0f); lineTo(w * 0.67f, h * 0.12f)
                    quadraticTo(w * 0.94f, h * 0.16f, w * 0.94f, h * 0.31f); lineTo(w * 0.94f, h * 0.88f)
                    quadraticTo(w * 0.94f, h, w * 0.81f, h); lineTo(w * 0.19f, h)
                    quadraticTo(w * 0.06f, h, w * 0.06f, h * 0.88f); lineTo(w * 0.06f, h * 0.31f)
                    quadraticTo(w * 0.06f, h * 0.16f, w * 0.33f, h * 0.12f); close()
                }
                drawPath(vessel, palette.jugGlass)
                if (level.value > 0f) {
                    clipPath(vessel) {
                        val surface = h * (1 - level.value)
                        val amplitude = 4f * u * slosh.value * sin(slosh.value * 6f * PI.toFloat())
                        val water = Path().apply {
                            moveTo(0f, surface)
                            for (step in 0..24) {
                                lineTo(w * step / 24f, surface + sin(step / 24f * PI.toFloat() * 2) * amplitude)
                            }
                            lineTo(w, h); lineTo(0f, h); close()
                        }
                        drawPath(water, palette.jugGradient)
                    }
                }
                drawPath(vessel, outline, style = Stroke(2.5f * u))
                drawRoundRect(Color.White.copy(alpha = 0.35f), topLeft = Offset(w / 2 - 21f * u - 2f * u, h / 2 + 14f * u - 27f * u),
                    size = GeometrySize(4f * u, 54f * u), cornerRadius = CornerRadius(2f * u))
            }
            // Lid
            drawRoundRect(palette.jugGlass, topLeft = Offset(19f * u, 3f * u), size = GeometrySize(28f * u, 8f * u), cornerRadius = CornerRadius(3f * u))
            drawRoundRect(outline, topLeft = Offset(19f * u, 3f * u), size = GeometrySize(28f * u, 8f * u), cornerRadius = CornerRadius(3f * u),
                style = Stroke(2f * u))
        }
        if (millilitres > goal) {
            Row(Modifier.offset(13.dp, 113.dp), horizontalArrangement = Arrangement.spacedBy(34.dp)) {
                repeat(2) { Icon(Icons.Filled.WaterDrop, null, tint = palette.water, modifier = Modifier.size(9.dp)) }
            }
        }
        if (spill > 0f) {
            Row(Modifier.offset(16.dp, (-2 - (1 - spill) * 12).dp).alpha(spill), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                repeat(3) { index ->
                    Icon(Icons.Filled.WaterDrop, null, tint = palette.water, modifier = Modifier.size(9.dp).offset(y = (index % 2 * 6).dp))
                }
            }
        }
    }
}

/**
 * The once-only celebration over the water section: sparkles and a badge, or just the badge
 * when animations are off. The ledger in `core` decides when it may play.
 */
@Composable
fun CompletionEffect(event: CelebrationEvent?, visible: Boolean, modifier: Modifier, onFinished: () -> Unit) {
    val still = reduceMotion()
    var progress by remember { mutableStateOf(0f) }
    var active by remember { mutableStateOf<CelebrationEvent?>(null) }
    LaunchedEffect(event?.id, visible) {
        active = if (visible) event else null
        val current = active ?: return@LaunchedEffect
        val millis = (current.duration * 1000).toLong()
        if (still) delay(millis) else {
            val start = System.nanoTime()
            while (true) {
                val elapsed = (System.nanoTime() - start) / 1_000_000L
                progress = (elapsed.toFloat() / millis).coerceAtMost(1f)
                if (elapsed >= millis) break
                delay(16)
            }
        }
        active = null
        onFinished()
    }
    val current = active ?: return
    val palette = P
    Box(modifier.clipToBounds(), contentAlignment = Alignment.Center) {
        if (!still) {
            val count = if (current.kind == CompletionCelebration.MILESTONE) 16 else 8
            repeat(count) { index ->
                val angle = index * PI / (count / 2)
                Icon(Icons.Filled.AutoAwesome, null, tint = palette.done,
                    modifier = Modifier.size(14.dp).offset((cos(angle) * (30 + progress * 110)).dp, (sin(angle) * (20 + progress * 55)).dp)
                        .alpha(1 - progress))
            }
        }
        val (text, icon) = when (current.kind) {
            CompletionCelebration.MILESTONE -> "75 consecutive days!" to Icons.Filled.EmojiEvents
            CompletionCelebration.EXTRAS -> "All extras done!" to Icons.Filled.Checklist
            CompletionCelebration.DAILY -> "All five complete!" to Icons.Filled.Verified
        }
        Row(Modifier.clip(CircleShape).background(palette.solidGlass).border(1.5.dp, palette.done, CircleShape)
            .padding(horizontal = 14.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(icon, null, tint = palette.doneText, modifier = Modifier.size(18.dp))
            Text(text, style = if (current.kind == CompletionCelebration.MILESTONE) Type.appName else Type.pill, color = palette.doneText)
        }
    }
}

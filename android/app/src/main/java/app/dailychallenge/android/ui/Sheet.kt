package app.dailychallenge.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp

/**
 * Where sheets draw: above the whole app, in the activity's own edge-to-edge window, so the
 * system bars keep the app's colours (Material's sheet opens a separate window that does not).
 */
class SheetHost {
    private var owner: Any? = null
    var content by mutableStateOf<(@Composable () -> Unit)?>(null)
        private set

    fun show(token: Any, sheet: @Composable () -> Unit) { owner = token; content = sheet }
    fun hide(token: Any) { if (owner == token) { owner = null; content = null } }
}

val LocalSheetHost = staticCompositionLocalOf<SheetHost?> { null }

/** Provides the host and draws the current sheet over [content]. */
@Composable
fun SheetHostBox(content: @Composable BoxScope.() -> Unit) {
    val host = remember { SheetHost() }
    CompositionLocalProvider(LocalSheetHost provides host) {
        Box(Modifier.fillMaxSize()) {
            content()
            host.content?.invoke()
        }
    }
}

/**
 * A sheet rising from the bottom over a scrim, on the app's backdrop with rounded top corners.
 * While it is in the composition it is shown; leave the composition to close it. Tapping the
 * scrim or the back gesture calls [onDismiss] unless [dismissible] is false (work in progress).
 */
@Composable
fun AppSheet(onDismiss: () -> Unit, dismissible: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    val host = LocalSheetHost.current ?: return
    val token = remember { Any() }
    SideEffect { host.show(token) { SheetPanel(onDismiss, dismissible, content) } }
    DisposableEffect(token) { onDispose { host.hide(token) } }
}

@Composable
private fun SheetPanel(onDismiss: () -> Unit, dismissible: Boolean, content: @Composable ColumnScope.() -> Unit) {
    val rise = remember { Animatable(1f) }
    val still = reduceMotion()
    LaunchedEffect(Unit) { if (still) rise.snapTo(0f) else rise.animateTo(0f, tween(260)) }
    BackHandler { if (dismissible) onDismiss() }
    val shape = RoundedCornerShape(topStart = Size.sheetRadius, topEnd = Size.sheetRadius)
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().graphicsLayer { alpha = 1f - rise.value }.background(Color.Black.copy(alpha = 0.4f))
            .pointerInput(dismissible) { detectTapGestures { if (dismissible) onDismiss() } })
        Box(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                .windowInsetsPadding(WindowInsets.statusBars).padding(top = 24.dp)
                .graphicsLayer { translationY = rise.value * size.height }
                .clip(shape)
                // Taps inside the panel never reach the scrim.
                .pointerInput(Unit) { detectTapGestures { } },
        ) {
            Backdrop(Modifier.matchParentSize())
            Column(Modifier.fillMaxWidth().navigationBarsPadding().imePadding(), content = content)
        }
    }
}

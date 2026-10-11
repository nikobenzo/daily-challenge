package app.dailychallenge.android.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/**
 * The Daily Challenge design system (docs/design-system.md), the same tokens as
 * `Sources/DailyChallengeProof/Shared/Theme.swift` and the iPhone backdrop, in Compose terms.
 * Every colour is one pair resolved against the device-local appearance.
 */
@Immutable
data class Palette(
    val dark: Boolean,
    val glass: Color, val solidGlass: Color, val glassBorder: Color, val glassHighlight: Color,
    val sheetShadow: Color, val hairline: Color,
    val controlFill: Color, val fieldFill: Color, val primaryTop: Color, val primaryBottom: Color, val primaryShadow: Color,
    val toggleOn: Color, val toggleOff: Color, val segmentSelected: Color, val focus: Color, val focusHalo: Color,
    val water: Color, val jugTop: Color, val jugBottom: Color, val accentText: Color, val accentTint: Color,
    val done: Color, val doneText: Color, val doneTint: Color, val onDone: Color,
    val amber: Color, val amberText: Color, val amberTint: Color,
    val danger: Color, val dangerRing: Color, val dangerTint: Color,
    val textPrimary: Color, val textSecondary: Color, val textTertiary: Color, val textInverse: Color,
    val futureDay: Color, val ringTrack: Color, val appMarkTop: Color, val appMarkBottom: Color,
    val dayBadgeFill: Color, val dayBadgeText: Color, val bestBadgeFill: Color, val bestBadgeText: Color,
    val jugOutline: Color, val jugGlass: Color,
    val backdropTop: Color, val backdropBottom: Color, val backdropGlow: Color,
) {
    val primaryGradient get() = Brush.verticalGradient(listOf(primaryTop, primaryBottom))
    val appMarkGradient get() = Brush.verticalGradient(listOf(appMarkTop, appMarkBottom))
    val jugGradient get() = Brush.verticalGradient(listOf(jugTop, jugBottom))
}

private fun hex(value: Long) = Color(0xFF000000 or value)
private fun rgba(r: Int, g: Int, b: Int, a: Float = 1f) = Color(r, g, b, (a * 255).toInt())

val DarkPalette = Palette(
    dark = true,
    glass = rgba(34, 38, 98, 0.62f), solidGlass = rgba(34, 38, 98), glassBorder = rgba(255, 255, 255, 0.16f),
    glassHighlight = rgba(255, 255, 255, 0.18f), sheetShadow = rgba(8, 10, 40, 0.45f), hairline = rgba(255, 255, 255, 0.10f),
    controlFill = rgba(255, 255, 255, 0.12f), fieldFill = rgba(255, 255, 255, 0.10f), primaryTop = hex(0x4A80FF),
    primaryBottom = hex(0x2A5BE8), primaryShadow = rgba(42, 91, 232, 0.45f), toggleOn = hex(0x2F6BFF),
    toggleOff = rgba(255, 255, 255, 0.18f), segmentSelected = rgba(255, 255, 255, 0.18f), focus = hex(0x6FA0FF),
    focusHalo = rgba(111, 160, 255, 0.25f), water = hex(0x5EA8FF), jugTop = hex(0x8CC4FF), jugBottom = hex(0x2E66F0),
    accentText = hex(0x8CC4FF), accentTint = rgba(140, 196, 255, 0.16f), done = hex(0x4DF0A3), doneText = hex(0x8DFFC6),
    doneTint = rgba(77, 240, 163, 0.18f), onDone = hex(0x0B2A1C), amber = hex(0xFF9F3D), amberText = hex(0xFFC27A),
    amberTint = rgba(255, 178, 74, 0.22f), danger = hex(0xFF8A8A), dangerRing = hex(0xFF7A7A),
    dangerTint = rgba(255, 138, 138, 0.16f), textPrimary = hex(0xFFFFFF), textSecondary = hex(0xC9CFF5),
    textTertiary = hex(0xA9B1DC), textInverse = hex(0x0F172A), futureDay = rgba(255, 255, 255, 0.35f),
    ringTrack = rgba(255, 255, 255, 0.14f), appMarkTop = hex(0x3D74FF), appMarkBottom = hex(0x1A3FA8),
    dayBadgeFill = rgba(255, 255, 255, 0.12f), dayBadgeText = hex(0xFFFFFF), bestBadgeFill = rgba(255, 255, 255, 0.12f),
    bestBadgeText = hex(0xFFFFFF), jugOutline = hex(0xC9CFF5), jugGlass = rgba(255, 255, 255, 0.10f),
    backdropTop = hex(0x1A2260), backdropBottom = hex(0x070A26), backdropGlow = rgba(74, 128, 255, 0.35f),
)

val LightPalette = Palette(
    dark = false,
    glass = rgba(255, 255, 255, 0.66f), solidGlass = rgba(246, 248, 253), glassBorder = rgba(255, 255, 255, 0.9f),
    glassHighlight = rgba(255, 255, 255, 0.9f), sheetShadow = rgba(30, 40, 90, 0.22f), hairline = rgba(15, 23, 42, 0.08f),
    controlFill = rgba(15, 23, 42, 0.07f), fieldFill = rgba(255, 255, 255, 0.8f), primaryTop = hex(0x3B72FF),
    primaryBottom = hex(0x1F56E0), primaryShadow = rgba(31, 86, 224, 0.35f), toggleOn = hex(0x1F56E0),
    toggleOff = rgba(15, 23, 42, 0.14f), segmentSelected = hex(0xFFFFFF), focus = hex(0x1F56E0),
    focusHalo = rgba(31, 86, 224, 0.18f), water = hex(0x2E66F0), jugTop = hex(0x6FB0FF), jugBottom = hex(0x1F56E0),
    accentText = hex(0x1F56E0), accentTint = rgba(31, 86, 224, 0.10f), done = hex(0x22C06A), doneText = hex(0x15803D),
    doneTint = rgba(34, 192, 106, 0.14f), onDone = hex(0xFFFFFF), amber = hex(0xF28C28), amberText = hex(0xB45309),
    amberTint = rgba(242, 140, 40, 0.16f), danger = hex(0xC62828), dangerRing = hex(0xC62828),
    dangerTint = rgba(198, 40, 40, 0.10f), textPrimary = hex(0x0F172A), textSecondary = hex(0x5B6478),
    textTertiary = hex(0x8A94A8), textInverse = hex(0xFFFFFF), futureDay = hex(0xB7BFCF),
    ringTrack = rgba(15, 23, 42, 0.10f), appMarkTop = hex(0x2E66F0), appMarkBottom = hex(0x0B2A8A),
    dayBadgeFill = rgba(31, 86, 224, 0.10f), dayBadgeText = hex(0x1F56E0), bestBadgeFill = rgba(242, 140, 40, 0.16f),
    bestBadgeText = hex(0xB45309), jugOutline = hex(0x8A94A8), jugGlass = rgba(255, 255, 255, 0.6f),
    backdropTop = hex(0xEAF1FF), backdropBottom = hex(0xD5E2FB), backdropGlow = rgba(111, 176, 255, 0.45f),
)

/** The type scale in sp, so it follows the system font size like Dynamic Type. */
object Type {
    val hero = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.Black, letterSpacing = (-0.03).em)
    val screenTitle = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.Black, letterSpacing = (-0.02).em)
    val streak = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Black)
    val appName = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.01).em)
    val rowLabel = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
    val pill = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Bold)
    val field = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium)
    val link = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Bold)
    val caption = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    val badge = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold)
    val ringLabel = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.06.em)
    val eyebrow = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.08.em)
}

object Size {
    val sheetRadius = 28.dp
    val sectionHorizontal = 20.dp
    val sectionVertical = 16.dp
    val pill = 42.dp
    val largePill = 48.dp
    val field = 46.dp
    val ring = 64.dp
    val ringStroke = 6.dp
}

val LocalPalette = staticCompositionLocalOf { LightPalette }

/** The current palette: `P.water`, `P.textPrimary`… */
val P: Palette @Composable get() = LocalPalette.current

@Composable
fun DailyChallengeTheme(dark: Boolean, content: @Composable () -> Unit) {
    val palette = if (dark) DarkPalette else LightPalette
    val scheme = if (dark) {
        darkColorScheme(primary = palette.primaryTop, onPrimary = Color.White, surface = palette.solidGlass,
            onSurface = palette.textPrimary, background = palette.backdropBottom, error = palette.danger,
            surfaceContainerHigh = palette.solidGlass, surfaceContainerLow = palette.solidGlass, surfaceContainer = palette.solidGlass)
    } else {
        lightColorScheme(primary = palette.primaryBottom, onPrimary = Color.White, surface = palette.solidGlass,
            onSurface = palette.textPrimary, background = palette.backdropTop, error = palette.danger,
            surfaceContainerHigh = palette.solidGlass, surfaceContainerLow = palette.solidGlass, surfaceContainer = palette.solidGlass)
    }
    CompositionLocalProvider(LocalPalette provides palette) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

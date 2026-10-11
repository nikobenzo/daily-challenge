package app.dailychallenge.android

import android.content.Context
import android.content.Intent

/** Release builds have no fixtures: every launch uses the real configuration (see src/debug). */
object Fixtures {
    @Suppress("UNUSED_PARAMETER")
    fun graph(context: Context, intent: Intent?): AppGraph? = null
}

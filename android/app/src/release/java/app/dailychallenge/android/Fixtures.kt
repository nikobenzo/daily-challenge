package app.dailychallenge.android

import android.content.Context
import android.content.Intent

/** Release builds have no fixtures: every launch uses the real configuration (see src/debug). */
object Fixtures {
    @Suppress("UNUSED_PARAMETER")
    fun graph(context: Context, intent: Intent?): AppGraph? = null

    @Suppress("UNUSED_PARAMETER")
    fun seedWidgets(context: Context, intent: Intent?): Boolean = false

    /** Widgets always read the real history. */
    @Suppress("UNUSED_PARAMETER")
    fun widgetDirectory(context: Context): java.io.File? = null
}

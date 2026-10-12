package app.dailychallenge.android

import android.app.Application
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import app.dailychallenge.android.ui.DailyChallengeTheme
import app.dailychallenge.android.ui.RootScreen
import app.dailychallenge.android.ui.SheetHostBox
import app.dailychallenge.android.widget.ChallengeWidgets
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min

class DailyChallengeApp : Application() {
    private val lazyGraph = lazy { AppGraph.production(this) }

    /** Created on first use, so a Debug fixture launch or a widget tap never opens the real session. */
    val graph: AppGraph by lazyGraph

    /** The running app's graph, if anything has created it; widget taps only ask it to reload. */
    val startedGraph: AppGraph? get() = if (lazyGraph.isInitialized()) graph else null

    override fun onCreate() {
        super.onCreate()
        AlarmReminderScheduler.createChannel(this)
    }

    /** Light or Dark, or the font size, changed: widgets before Android 12 draw their colours themselves. */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        ChallengeWidgets.requestRefresh(this, force = true)
    }
}

class MainActivity : ComponentActivity() {
    private lateinit var graph: AppGraph
    private var onScreen by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Debug only: seeds the widgets' fixture history and leaves (Fixtures.seedWidgets).
        if (Fixtures.seedWidgets(this, intent)) {
            finish()
            return
        }
        graph = Fixtures.graph(this, intent) ?: (application as DailyChallengeApp).graph
        open(intent)
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.auto(0, 0), navigationBarStyle = SystemBarStyle.auto(0, 0))
        setContent {
            val dark = when (graph.appearance) {
                Appearance.SYSTEM -> isSystemInDarkTheme()
                Appearance.LIGHT -> false
                Appearance.DARK -> true
            }
            LaunchedEffect(dark) {
                enableEdgeToEdge(
                    statusBarStyle = if (dark) SystemBarStyle.dark(0) else SystemBarStyle.light(0, 0),
                    navigationBarStyle = if (dark) SystemBarStyle.dark(0) else SystemBarStyle.light(0, 0),
                )
            }
            DailyChallengeTheme(dark) { SheetHostBox { RootScreen(graph, onScreen) } }
        }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                onScreen = true
                if (!graph.isFixture) graph.becameActive()
                // While on screen: sync every 30 seconds, as the Apple apps do.
                if (!graph.isFixture) launch { graph.tracker.syncWhileVisible() }
                // Midnight in the challenge's zone rolls Today over while the app stays open.
                launch {
                    while (true) {
                        val now = graph.tracker.now
                        val midnight = graph.tracker.dates.calendar.interval(now).second
                        delay((max(0.1, min(30.0, midnight - now)) * 1000).toLong())
                        if (!graph.isFixture) graph.tracker.refresh()
                    }
                }
                try {
                    kotlinx.coroutines.awaitCancellation()
                } finally {
                    onScreen = false
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (Fixtures.seedWidgets(this, intent)) return
        setIntent(intent)
        open(intent)
    }

    /** A widget opened the app: Today, or Manage extras once signed in with a challenge (RootScreen gates it). */
    private fun open(intent: Intent?) {
        when (intent?.getStringExtra(DESTINATION)) {
            "today" -> { graph.tab = Tab.TODAY; graph.tracker.showToday() }
            "extras" -> { graph.tab = Tab.TODAY; graph.tracker.showToday(); graph.manageExtrasRequested = true }
        }
    }

    companion object {
        const val DESTINATION = "destination"
    }
}

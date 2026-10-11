package app.dailychallenge.android

import android.app.Application
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
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min

class DailyChallengeApp : Application() {
    /** Created on first use, so a Debug fixture launch never opens the real session or history. */
    val graph: AppGraph by lazy { AppGraph.production(this) }

    override fun onCreate() {
        super.onCreate()
        AlarmReminderScheduler.createChannel(this)
    }
}

class MainActivity : ComponentActivity() {
    private lateinit var graph: AppGraph
    private var onScreen by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        graph = Fixtures.graph(this, intent) ?: (application as DailyChallengeApp).graph
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
}

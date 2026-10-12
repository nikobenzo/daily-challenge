package app.dailychallenge.android.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.updateAll
import app.dailychallenge.android.AppGraph
import app.dailychallenge.android.DailyChallengeApp
import app.dailychallenge.android.Fixtures
import app.dailychallenge.android.SyncWorker
import app.dailychallenge.core.ChallengeTime
import app.dailychallenge.core.WidgetActions
import app.dailychallenge.core.WidgetBinding
import app.dailychallenge.core.WidgetOutcome
import app.dailychallenge.core.WidgetState
import app.dailychallenge.core.WidgetTap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/**
 * The three home-screen widgets (the iPhone's Water, Daily requirements and Extras). They read
 * the history folder and the account the app publishes, record taps into the same pending queue
 * under the same lock as the app, and never hold a session or reach the network. The app's
 * sync uploads what they record. Redraws happen after changes, after sync, at midnight in the
 * challenge's zone and on a theme change, never on a timer.
 */
object ChallengeWidgets {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val mutex = Mutex()
    private var lastDrawn: WidgetState? = null
    private val _version = MutableStateFlow(0L)

    /** Ticks on every redraw so a widget composition that is still running reloads its data. */
    val version: StateFlow<Long> = _version

    /** The history the widgets read: the app's own folder (Debug builds may point them at fixtures). */
    fun directory(context: Context): File = Fixtures.widgetDirectory(context) ?: AppGraph.dataDirectory(context)

    fun load(context: Context, now: Double = ChallengeTime.now()): WidgetState = WidgetState.load(directory(context), now)

    /** Fire and forget; `force` redraws even when the data looks unchanged (a theme or font change). */
    fun requestRefresh(context: Context, force: Boolean = false) {
        val app = context.applicationContext
        scope.launch { refresh(app, force) }
    }

    suspend fun refresh(context: Context, force: Boolean = false) = mutex.withLock {
        val state = withContext(Dispatchers.IO) { load(context) }
        val placed = placedCount(context) > 0
        scheduleMidnight(context, state.takeIf { placed })
        // Sync merges commit every 30 seconds while the app is open; redraw only on a change.
        if (!placed || (!force && state == lastDrawn)) return@withLock
        lastDrawn = state
        _version.value += 1
        widgets.forEach { it.updateAll(context) }
    }

    private val widgets: List<GlanceAppWidget> get() = listOf(WaterWidget(), RequirementsWidget(), ExtrasWidget())
    private val receivers = listOf(WaterWidgetReceiver::class.java, RequirementsWidgetReceiver::class.java, ExtrasWidgetReceiver::class.java)

    private fun placedCount(context: Context): Int {
        val manager = AppWidgetManager.getInstance(context) ?: return 0
        return receivers.sumOf { manager.getAppWidgetIds(ComponentName(context, it)).size }
    }

    /**
     * One inexact alarm at the next midnight in the challenge's zone, replaced on every refresh.
     * It does not wake the phone: a sleeping phone shows no widgets, and it fires on the next wake.
     */
    private fun scheduleMidnight(context: Context, state: WidgetState?) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = PendingIntent.getBroadcast(context, 0, Intent(context, WidgetMidnightReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        if (state !is WidgetState.Ready) {
            alarms.cancel(intent)
            return
        }
        val at = (ChallengeTime.toUnix(state.nextMidnight + 1) * 1000).toLong()
        alarms.setWindow(AlarmManager.RTC, at, MIDNIGHT_WINDOW_MILLIS, intent)
    }

    /**
     * A tap: recorded under the store lock from the state on disk at the tap's own time. After a
     * recorded change the open app reloads, and one sync is queued through the app's own worker.
     */
    suspend fun perform(context: Context, tap: WidgetTap, binding: WidgetBinding): WidgetOutcome {
        val directory = directory(context)
        val outcome = withContext(Dispatchers.IO) {
            try {
                WidgetActions(directory).perform(tap, binding)
            } catch (_: Exception) {
                // Nothing was saved (commits are atomic); the redraw shows the stored state.
                WidgetOutcome.Refused
            }
        }
        if (outcome is WidgetOutcome.Recorded && Fixtures.widgetDirectory(context) == null) {
            (context.applicationContext as? DailyChallengeApp)?.startedGraph?.let { graph ->
                withContext(Dispatchers.Main) { graph.tracker.reload() }
            }
            SyncWorker.requestSoon(context)
        }
        refresh(context, force = true)
        return outcome
    }

    private const val MIDNIGHT_WINDOW_MILLIS = 60_000L
}

/** Every tappable control: which tap, plus the binding it was drawn with. */
class WidgetTapCallback : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val tap = WidgetTap.parse(parameters[Keys.kind], parameters[Keys.target])
        val generation = parameters[Keys.generation]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
        val challenge = parameters[Keys.challenge]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
        if (tap == null || generation == null || challenge == null) {
            ChallengeWidgets.refresh(context, force = true)
            return
        }
        ChallengeWidgets.perform(context, tap, WidgetBinding(generation, challenge))
    }

    object Keys {
        val kind = ActionParameters.Key<String>("kind")
        val target = ActionParameters.Key<String>("target")
        val generation = ActionParameters.Key<String>("generation")
        val challenge = ActionParameters.Key<String>("challenge")
    }
}

/** The next challenge day has begun: draw it (zero water, pending ticks, carried-over extras). */
class WidgetMidnightReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                ChallengeWidgets.refresh(context.applicationContext)
            } finally {
                pending.finish()
            }
        }
    }
}

abstract class ChallengeWidgetReceiver : GlanceAppWidgetReceiver() {
    /** Also after a restart or an app update, which clear alarms: arm the next midnight again. */
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        ChallengeWidgets.requestRefresh(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        ChallengeWidgets.requestRefresh(context, force = true)
    }

    /** The last of this kind was removed: the midnight alarm stays only while any widget is placed. */
    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        ChallengeWidgets.requestRefresh(context)
    }
}

class WaterWidgetReceiver : ChallengeWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = WaterWidget()
}

class RequirementsWidgetReceiver : ChallengeWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = RequirementsWidget()
}

class ExtrasWidgetReceiver : ChallengeWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ExtrasWidget()
}

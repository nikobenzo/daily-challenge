package app.dailychallenge.android

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.dailychallenge.android.widget.ChallengeWidgets
import app.dailychallenge.core.AuthModel
import app.dailychallenge.core.ChallengeTime
import app.dailychallenge.core.DeviceWording
import app.dailychallenge.core.KeyValueStore
import app.dailychallenge.core.SupabaseAccountDeletion
import app.dailychallenge.core.SupabaseAuth
import app.dailychallenge.core.SupabaseChallengeTransport
import app.dailychallenge.core.SupabaseConfiguration
import app.dailychallenge.core.SupabaseHttp
import app.dailychallenge.core.Tracker
import app.dailychallenge.core.WaterReminderController
import app.dailychallenge.core.WidgetAccountStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import java.io.File

enum class Tab { TODAY, HISTORY, ACCOUNT }

/** Device-local appearance: System follows Android. Never synced. */
enum class Appearance(val key: String, val label: String) {
    SYSTEM("system", "System"), LIGHT("light", "Light"), DARK("dark", "Dark");

    companion object {
        fun of(key: String?) = entries.firstOrNull { it.key == key } ?: SYSTEM
    }
}

/** Debug-only fixture switches; always off in release builds. */
data class FixtureOptions(
    val showManagement: Boolean = false,
    val showDeletion: Boolean = false,
    val showDeletionConfirmation: Boolean = false,
    /** Opens Account › Daily goals, and with [editGoal] (`water`, `workout`, `walk`, `diet`, `bibleReading`) that editor; also setup's. */
    val showGoals: Boolean = false,
    val editGoal: String? = null,
    /** Opens Manage extras editing the extra with this title. */
    val editExtra: String? = null,
)

/**
 * The app's composition root (the iPhone's `PhoneApp`): the shared auth, tracker and reminder
 * models from `core`, wired to Android's lifecycle, WorkManager and connectivity.
 */
class AppGraph(
    val auth: AuthModel,
    val tracker: Tracker,
    val reminders: WaterReminderController?,
    private val prefs: KeyValueStore,
    val scope: CoroutineScope,
    private val context: Context?,
    val isFixture: Boolean,
    val fixture: FixtureOptions = FixtureOptions(),
    /** The clock auth countdowns read; fixtures pin it. */
    val clock: () -> Double = ChallengeTime::now,
) {
    var tab by mutableStateOf(Tab.TODAY)
    var manageExtrasRequested by mutableStateOf(false)
    var appearance by mutableStateOf(Appearance.of(prefs.getString(APPEARANCE_KEY)))
        private set

    fun chooseAppearance(value: Appearance) {
        appearance = value
        prefs.putString(APPEARANCE_KEY, value.key)
    }

    fun markNotificationsAsked() = prefs.putString(AlarmReminderScheduler.ASKED_KEY, "1")

    /** Ticks when reminder settings, permission or plan change, so Account redraws. */
    var reminderChanges by mutableStateOf(0)
        private set

    init {
        tracker.reminders = reminders
        reminders?.onChange = { reminderChanges++ }
    }

    /**
     * Deletes the account on the server, then this phone's copy of it. Nothing changes
     * unless the server confirms (AuthModel.deleteAccount). Returns whether it was deleted.
     */
    suspend fun deleteAccount(): Boolean {
        val deleted = auth.deleteAccount(tracker::removeLocalData)
        if (deleted) tab = Tab.TODAY
        return deleted
    }

    /** Foreground: catch up on the day, reminders and the server. */
    fun becameActive() {
        tracker.reload()
        tracker.refresh()
        reminders?.reconcile()
        tracker.requestSync()
    }

    /** One background run: sync once and re-plan reminders. */
    suspend fun backgroundRefresh() {
        tracker.reload()
        tracker.refresh()
        tracker.sync(force = true)
        tracker.refreshReminders()
    }

    companion object {
        const val APPEARANCE_KEY = "appearancePreference"

        private val configuration: SupabaseConfiguration? get() =
            SupabaseConfiguration.from(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_PUBLISHABLE_KEY)

        /** One folder per Supabase project, so a differently configured build never mixes histories. */
        fun dataDirectory(context: Context): File =
            File(context.filesDir, "DailyChallenge/${configuration?.projectRef ?: "unconfigured"}")

        /** The real app: configuration from the build, the Keystore session, real alarms and sync. */
        fun production(context: Context): AppGraph {
            val prefs = SharedPrefsStore(context)
            val configuration = configuration
            val scope = MainScope()
            val project = configuration?.projectRef ?: "unconfigured"
            val directory = dataDirectory(context)
            val tracker = Tracker(directory, scope)
            val reminders = WaterReminderController(prefs, AlarmReminderScheduler(context, prefs), DeviceWording.android)
            val auth = if (configuration != null) {
                val http = SupabaseHttp(configuration)
                val supabase = SupabaseAuth(http, KeystoreSessionStore(context, project))
                tracker.configureSync(SupabaseChallengeTransport(http, supabase), automatic = true)
                AuthModel(supabase, SupabaseAccountDeletion(http, supabase))
            } else {
                AuthModel(null, missingConfiguration =
                    "This build has no server configuration. Build it with .env.local at the repository root (docs/android.md).")
            }
            val graph = AppGraph(auth, tracker, reminders, prefs, scope, context.applicationContext, isFixture = false)
            // Widgets see only the account published here, and redraw after every committed change.
            val widgetAccount = WidgetAccountStore(directory)
            tracker.onCommitted = { ChallengeWidgets.requestRefresh(context) }
            auth.onSessionChange { owner ->
                graph.tab = Tab.TODAY
                SyncWorker.schedule(context, owner != null)
                try {
                    widgetAccount.publish(owner)
                } catch (_: Exception) {
                    // Unpublishing failed: the widgets keep the earlier account until the next change.
                }
                ChallengeWidgets.requestRefresh(context)
            }
            auth.attachTracker(tracker)
            auth.start()
            SyncWorker.schedule(context, auth.ownerID != null)
            // Back online: sync now rather than at the next 30-second check.
            val main = Handler(Looper.getMainLooper())
            context.getSystemService(ConnectivityManager::class.java)?.registerDefaultNetworkCallback(
                object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) { main.post { tracker.requestSync() } }
                },
            )
            return graph
        }
    }
}

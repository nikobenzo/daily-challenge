package app.dailychallenge.android

import android.content.Context
import android.content.Intent
import app.dailychallenge.core.AccountDeletionTransport
import app.dailychallenge.core.Action
import app.dailychallenge.core.AuthBackend
import app.dailychallenge.core.AuthModel
import app.dailychallenge.core.AuthSession
import app.dailychallenge.core.AuthStep
import app.dailychallenge.core.ChallengeCalendar
import app.dailychallenge.core.ChallengeEvent
import app.dailychallenge.core.ChallengeRecord
import app.dailychallenge.core.ChallengeSyncError
import app.dailychallenge.core.ChallengeSyncException
import app.dailychallenge.core.ChallengeTime
import app.dailychallenge.core.ChallengeTransport
import app.dailychallenge.core.DeviceWording
import app.dailychallenge.core.DietState
import app.dailychallenge.core.ExtraSchedule
import app.dailychallenge.core.Habit
import app.dailychallenge.core.MemoryKeyValueStore
import app.dailychallenge.core.NetworkException
import app.dailychallenge.core.NotificationPermission
import app.dailychallenge.core.OtpType
import app.dailychallenge.core.RemoteEvents
import app.dailychallenge.core.ReminderScheduler
import app.dailychallenge.core.SignUpResult
import app.dailychallenge.core.Target
import app.dailychallenge.core.TargetUnit
import app.dailychallenge.core.Targets
import app.dailychallenge.core.Tracker
import app.dailychallenge.core.WaterReminderController
import app.dailychallenge.core.WaterReminderSettings
import app.dailychallenge.core.WaterTarget
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.io.IOException
import java.time.ZoneId
import java.util.UUID

/**
 * Debug builds only: launching with `--es fixture <screen>` opens offline fixture data in a
 * temporary folder, for UI tests and screenshots. No configuration, session, network, alarm
 * or notification is touched, and release builds do not contain this file
 * (`src/release/.../Fixtures.kt` returns null).
 *
 *     adb shell am start -n app.dailychallenge.android/.MainActivity --es fixture today --es appearance dark
 */
object Fixtures {
    /** 9 October 2026, 15:00 in Jersey: a fixed clock keeps renders identical. */
    val now: Double = ChallengeTime.parse("2026-10-09T14:00:00Z")
    val zone: ZoneId = ZoneId.of("Europe/Jersey")
    val owner: UUID = UUID.fromString("6F1C2A43-0B55-4B5E-9F3D-2C1A7E9B4D10")

    /** The widgets' fixture history while a widget fixture is on, else null (the real history). */
    fun widgetDirectory(context: Context): File? = WidgetFixtures.directory(context)

    fun seedWidgets(context: Context, intent: Intent?): Boolean = WidgetFixtures.seed(context, intent)

    fun graph(context: Context, intent: Intent?): AppGraph? {
        val screen = intent?.getStringExtra("fixture") ?: return null
        return make(context, screen, intent.getStringExtra("appearance"), FixtureOptions(
            showManagement = intent.getBooleanExtra("manageExtras", false),
            showDeletion = intent.getBooleanExtra("deleteAccount", false) || intent.getBooleanExtra("deleteAccountConfirm", false),
            showDeletionConfirmation = intent.getBooleanExtra("deleteAccountConfirm", false),
            showGoals = intent.getBooleanExtra("dailyGoals", false),
            editGoal = intent.getStringExtra("editGoal"),
            editExtra = intent.getStringExtra("editExtra"),
        ), deletionFails = intent.getBooleanExtra("deletionFails", false))
    }

    fun make(context: Context, screen: String, appearance: String? = null, options: FixtureOptions = FixtureOptions(),
             deletionFails: Boolean = false): AppGraph {
        context.cacheDir.listFiles { file -> file.name.startsWith("fixture-") }?.forEach { it.deleteRecursively() }
        val directory = File(context.cacheDir, "fixture-${UUID.randomUUID()}")
        val prefs = MemoryKeyValueStore()
        appearance?.let { prefs.putString(AppGraph.APPEARANCE_KEY, it) }
        var clock = now
        val scope = MainScope()
        val auth = AuthModel(OfflineAuthBackend(), FixtureAccountDeletion(reachable = !deletionFails), now = { now })
        when (screen) {
            "signIn" -> auth.applyFixture(null)
            "createAccount" -> auth.applyFixture(null, step = AuthStep.CreateAccount)
            "forgotPassword" -> auth.applyFixture(null, step = AuthStep.ForgotPassword)
            "confirmCode" -> auth.applyFixture(null, step = AuthStep.ConfirmSignUp("sam@example.com"),
                notice = "We emailed a code to sam@example.com. Enter it to finish creating your account.", resendAvailableAt = now + 42)
            "resetPassword" -> auth.applyFixture(null, step = AuthStep.ResetPassword("sam@example.com"),
                notice = "If sam@example.com has an account, we emailed it a code. Enter it with your new password.")
            else -> auth.applyFixture(owner, email = "sam@example.com")
        }
        val reminders = WaterReminderController(prefs, FixtureScheduler(), DeviceWording.android) { clock }
        val tracker = Tracker(directory, scope, clock = { clock }, deviceZone = { zone })
        val graph = AppGraph(auth, tracker, reminders, prefs, scope, context.applicationContext, isFixture = true, fixture = options,
            clock = { now })
        auth.attachTracker(tracker)
        fun day(offset: Long) = ChallengeCalendar(zone).addDays(now, offset) + 12 * 3_600
        fun extraID(title: String) = tracker.challenge!!.allExtras.first { it.title == title }.id

        val goals = setOf("todayGoals", "historyGoals", "historyBeforeGoals", "accountGoals", "goalsServerUpdate")
        val seeded = setOf("today", "todayComplete", "history", "account", "todayExtras", "extrasCap", "historyExtras",
            "historyExtrasEditing", "accountExtras", "historyCarryOver", "todayRepeating") + goals
        when (screen) {
            "checking" -> tracker.configureSync(UnreachableTransport())
            in seeded -> {
                // Twelve days in: ten complete, one missed, and today in progress (or complete).
                val complete = screen == "todayComplete"
                tracker.startChallenge(ChallengeCalendar(zone).localDate(day(-11)), zone)
                for (offset in -11L..-1L) {
                    if (offset == -7L) continue
                    tracker.selectHistoryDay(day(offset)); tracker.enableCorrections()
                    repeat(9) { tracker.addWater() }
                    tracker.toggle(Habit.WORKOUT); tracker.toggle(Habit.WALK)
                    tracker.setDiet(DietState.CLEAN); tracker.toggle(Habit.BIBLE_READING)
                }
                tracker.selectHistoryDay(day(-7)); tracker.enableCorrections()
                tracker.addWater(1_800); tracker.toggle(Habit.WORKOUT)
                tracker.showToday()
                repeat(if (complete) 9 else 5) { tracker.addWater() }
                tracker.toggle(Habit.WORKOUT); tracker.setDiet(DietState.CLEAN)
                if (complete) { tracker.toggle(Habit.WALK); tracker.toggle(Habit.BIBLE_READING) }
                tracker.clearCelebration()

                if (screen in setOf("todayExtras", "extrasCap", "historyExtras", "historyExtrasEditing", "accountExtras", "historyCarryOver")) {
                    // Carry-over: two added two days ago and still open (late), one done then (gone),
                    // and one added and done today.
                    clock = day(-2); tracker.showToday()
                    listOf("Stretch", "Read a chapter", "Call family").forEach { tracker.addExtra(it) }
                    tracker.toggleExtra(extraID("Call family"))
                    clock = now; tracker.showToday()
                    tracker.addExtra("Prepare tomorrow’s healthy lunch")
                    tracker.toggleExtra(extraID("Prepare tomorrow’s healthy lunch"))
                    tracker.clearCelebration()
                    if (screen == "extrasCap") {
                        listOf("Practise gratitude", "Water the plants", "Tidy desk", "Journal", "Go outside", "Sleep on time",
                            "Back up photos", "A readable extra title of forty letters!").forEach { tracker.addExtra(it) }
                    }
                    if (screen == "historyExtras" || screen == "historyExtrasEditing") {
                        val archived = extraID("Read a chapter")
                        tracker.selectHistoryDay(day(-2)); tracker.enableCorrections()
                        tracker.toggleExtra(archived)
                        tracker.archiveExtra(archived)
                        tracker.selectHistoryDay(day(-2))
                        graph.tab = Tab.HISTORY
                        if (screen == "historyExtrasEditing") tracker.enableCorrections()
                    }
                }
                if (screen in goals) {
                    // Changed from today (day 12): earlier days keep the standard five.
                    tracker.setGoals(customGoals)
                    tracker.addWater(330)
                    tracker.clearCelebration()
                    when (screen) {
                        "historyGoals" -> { graph.tab = Tab.HISTORY; tracker.selectHistoryDay(tracker.today) }
                        "historyBeforeGoals" -> { graph.tab = Tab.HISTORY; tracker.selectHistoryDay(day(-2)) }
                        "accountGoals" -> graph.tab = Tab.ACCOUNT
                        "goalsServerUpdate" -> {
                            graph.tab = Tab.ACCOUNT
                            tracker.configureSync(UnmigratedTransport())
                            scope.launch { tracker.sync(force = true) }
                        }
                    }
                }
                if (screen == "todayRepeating") {
                    // Repeating extras beside a late to-do; Friday 9 October is a weekday.
                    clock = day(-2); tracker.showToday()
                    tracker.addExtra("Book dentist")
                    tracker.addExtra("Stretch", ExtraSchedule.Every(1))
                    tracker.addExtra("Pack lunch", ExtraSchedule.Weekdays((1..5).toSet()))
                    tracker.addExtra("Call family", ExtraSchedule.Weekdays(setOf(5)))
                    tracker.addExtra("Water the plants", ExtraSchedule.Every(3))
                    clock = now; tracker.showToday()
                    tracker.toggleExtra(extraID("Stretch"))
                    tracker.toggleExtra(extraID("Call family"))
                    tracker.clearCelebration()
                }
                if (screen == "history") { graph.tab = Tab.HISTORY; tracker.selectHistoryDay(day(-2)) }
                if (screen == "historyCarryOver") { graph.tab = Tab.HISTORY; tracker.selectHistoryDay(day(-1)) }
                if (screen == "account" || screen == "accountExtras") {
                    graph.tab = Tab.ACCOUNT
                    reminders.update(WaterReminderSettings(enabled = true))
                }
            }
        }
        if (options.showDeletion) graph.tab = Tab.ACCOUNT
        return graph
    }
}

/** The goals the custom-goals fixtures change to on day 12, as in the plan's wireframes. */
private val customGoals = Targets(
    WaterTarget(3_000, 330),
    Target("Gym", 45, TargetUnit.MINUTES),
    Target("Yoga", 30, TargetUnit.MINUTES, "yoga"),
    Target("No sugar"),
    Target("Audiobook", 20, TargetUnit.MINUTES, "headphones"),
)

/**
 * An in-memory server without the custom goals update: it keeps the challenge and older kinds,
 * and refuses a batch holding a target or schedule as Supabase does (23514 on the action-kind check).
 */
private class UnmigratedTransport : ChallengeTransport {
    private var header: ChallengeRecord? = null
    private val events = LinkedHashMap<UUID, ChallengeEvent>()
    override suspend fun fetchChallenge(ownerID: UUID): ChallengeRecord? = header
    override suspend fun insertChallenge(record: ChallengeRecord) { if (header == null) header = record }
    override suspend fun upload(events: List<ChallengeEvent>, ownerID: UUID) {
        if (events.any { it.activity.action.let { action -> action is Action.SetTarget || action is Action.SetWater || action is Action.ScheduleExtra } }) {
            throw ChallengeSyncException(ChallengeSyncError.SERVER_NEEDS_CUSTOM_GOALS_UPDATE)
        }
        events.forEach { this.events.putIfAbsent(it.id, it.copy(receivedAt = "2026-10-09T14:00:00Z")) }
    }
    override suspend fun fetchEvents(ownerID: UUID, challengeID: UUID): RemoteEvents = RemoteEvents(events.values.toList())
}

/** Reports permission as allowed and keeps nothing: no alarm is ever set by a fixture. */
private class FixtureScheduler : ReminderScheduler {
    override fun permission() = NotificationPermission.ALLOWED
    override fun replace(dates: List<Double>, zone: ZoneId) = Unit
    override fun cancel() = Unit
}

/** No server: every request fails as offline, so a fixture can never reach a real account. */
private class OfflineAuthBackend : AuthBackend {
    override var session: AuthSession? = null
    private fun offline(): Nothing = throw NetworkException(IOException("fixture: no server"))
    override fun onSessionChange(listener: (AuthSession?) -> Unit) = Unit
    override suspend fun signIn(email: String, password: String): AuthSession = offline()
    override suspend fun signUp(email: String, password: String): SignUpResult = offline()
    override suspend fun verifyOtp(email: String, token: String, type: OtpType): AuthSession? = offline()
    override fun adopt(session: AuthSession) = Unit
    override suspend fun resetPasswordForEmail(email: String) = offline()
    override suspend fun resendSignUp(email: String) = offline()
    override suspend fun updatePassword(password: String, session: AuthSession?) = offline()
    override suspend fun signOutLocal(session: AuthSession?) = Unit
}

/** Delete account against no server: succeeds after a short visible pause, or fails as offline. */
private class FixtureAccountDeletion(private val reachable: Boolean) : AccountDeletionTransport {
    override suspend fun deleteAccount(ownerID: UUID) {
        delay(500)
        if (!reachable) throw NetworkException(IOException("fixture: offline"))
    }
}

/** A server that cannot be reached, so setup waits on "Checking for your existing challenge". */
private class UnreachableTransport : ChallengeTransport {
    private fun offline(): Nothing = throw NetworkException(IOException("fixture: offline"))
    override suspend fun fetchChallenge(ownerID: UUID): ChallengeRecord? = offline()
    override suspend fun insertChallenge(record: ChallengeRecord) = offline()
    override suspend fun upload(events: List<ChallengeEvent>, ownerID: UUID) = offline()
    override suspend fun fetchEvents(ownerID: UUID, challengeID: UUID): RemoteEvents = offline()
}

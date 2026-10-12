package app.dailychallenge.android

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import app.dailychallenge.android.widget.ChallengeWidgets
import app.dailychallenge.android.widget.ExtrasWidgetReceiver
import app.dailychallenge.android.widget.RequirementsWidgetReceiver
import app.dailychallenge.android.widget.WaterWidgetReceiver
import app.dailychallenge.core.Action
import app.dailychallenge.core.ChallengeCalendar
import app.dailychallenge.core.ChallengeStore
import app.dailychallenge.core.ChallengeTime
import app.dailychallenge.core.DietState
import app.dailychallenge.core.Habit
import app.dailychallenge.core.WidgetAccountStore
import java.io.File
import java.util.UUID

/**
 * Debug builds only: `--es widgetFixture <name>` writes synthetic history for the home-screen
 * widgets into their own folder, points the widgets at it (their taps then record there) and
 * redraws them; `off` points them back at the real history. The day is today in Jersey, twelve
 * days in. The real session and history are never read or changed. `--es pinWidget
 * water|requirements|extras` also asks the launcher to place one.
 *
 *     adb shell am start -n app.dailychallenge.android/.MainActivity --es widgetFixture partial
 *
 * Fixtures: partial, empty, complete, over, missedDiet, extrasMany, signedOut, noChallenge, off.
 */
object WidgetFixtures {
    private const val MARKER = "widget-fixture-enabled"
    private const val FOLDER = "WidgetFixtures"

    fun directory(context: Context): File? =
        if (File(context.filesDir, MARKER).exists()) File(context.filesDir, FOLDER) else null

    fun seed(context: Context, intent: Intent?): Boolean {
        val name = intent?.getStringExtra("widgetFixture") ?: return false
        val marker = File(context.filesDir, MARKER)
        val folder = File(context.filesDir, FOLDER)
        folder.deleteRecursively()
        if (name == "off") marker.delete() else {
            write(folder, name)
            marker.writeText("1")
        }
        intent.getStringExtra("pinWidget")?.let { pin(context, it) }
        ChallengeWidgets.requestRefresh(context, force = true)
        return true
    }

    private fun pin(context: Context, kind: String) {
        val receiver = when (kind) {
            "water" -> WaterWidgetReceiver::class.java
            "requirements" -> RequirementsWidgetReceiver::class.java
            "extras" -> ExtrasWidgetReceiver::class.java
            else -> return
        }
        AppWidgetManager.getInstance(context).requestPinAppWidget(ComponentName(context, receiver), null, null)
    }

    private fun write(folder: File, name: String) {
        if (name == "signedOut") return
        WidgetAccountStore(folder).publish(Fixtures.owner)
        if (name == "noChallenge") return
        val zone = Fixtures.zone
        val calendar = ChallengeCalendar(zone)
        val now = ChallengeTime.now()
        fun day(offset: Long) = calendar.addDays(now, offset)
        val store = ChallengeStore(Fixtures.owner, folder)
        fun record(action: Action, at: Double) = store.record(action, at, at)
        store.start(day(-11), zone)
        // Ten complete days and one missed, so today is day 12 with a streak of 6.
        for (offset in -11L..-1L) {
            val at = day(offset) + 12 * 3_600
            if (offset == -7L) {
                record(Action.Pour(1_800), at)
                record(Action.SetHabit(Habit.WORKOUT, true), at)
                continue
            }
            repeat(9) { record(Action.Pour(450), at) }
            Habit.entries.forEach { record(Action.SetHabit(it, true), at) }
            record(Action.SetDiet(DietState.CLEAN), at)
        }
        val today = maxOf(day(0), now - 60)
        if (name == "empty") return
        // Two extras added two days ago and still open (late), one done that day, one added and done today.
        val added = day(-2) + 9 * 3_600
        val ids = listOf("Stretch", "Read a chapter", "Call family").associateWith { UUID.randomUUID() }
        ids.forEach { (title, id) -> record(Action.DefineExtra(id, title), added) }
        record(Action.SetExtra(ids.getValue("Call family"), true), added + 60)
        val lunch = UUID.randomUUID()
        record(Action.DefineExtra(lunch, "Prepare tomorrow’s healthy lunch"), today)
        record(Action.SetExtra(lunch, true), today)
        when (name) {
            "complete", "over" -> {
                repeat(if (name == "over") 10 else 9) { record(Action.Pour(450), today) }
                Habit.entries.forEach { record(Action.SetHabit(it, true), today) }
                record(Action.SetDiet(DietState.CLEAN), today)
            }
            "missedDiet" -> {
                repeat(2) { record(Action.Pour(450), today) }
                record(Action.SetHabit(Habit.WALK, true), today)
                record(Action.SetDiet(DietState.MISSED), today)
            }
            else -> {
                repeat(3) { record(Action.Pour(450), today) }
                record(Action.SetHabit(Habit.WORKOUT, true), today)
            }
        }
        if (name == "extrasMany") {
            listOf("Practise gratitude", "Water the plants", "Tidy desk", "Journal", "Go outside", "Sleep on time",
                "A readable extra title of forty letters!").forEach { record(Action.DefineExtra(UUID.randomUUID(), it), today) }
        }
    }
}

package app.dailychallenge.android

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.action.actionParametersOf
import androidx.glance.appwidget.testing.unit.hasRunCallbackClickAction
import androidx.glance.appwidget.testing.unit.hasStartActivityClickAction
import androidx.glance.appwidget.testing.unit.runGlanceAppWidgetUnitTest
import androidx.glance.testing.unit.hasClickAction
import androidx.glance.testing.unit.hasContentDescription
import androidx.glance.testing.unit.hasContentDescriptionEqualTo
import androidx.glance.testing.unit.hasNoClickAction
import androidx.glance.testing.unit.hasText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.dailychallenge.android.widget.Destination
import app.dailychallenge.android.widget.ExtrasContent
import app.dailychallenge.android.widget.RequirementsContent
import app.dailychallenge.android.widget.WaterContent
import app.dailychallenge.android.widget.WidgetSurface
import app.dailychallenge.android.widget.WidgetTapCallback
import app.dailychallenge.core.Action
import app.dailychallenge.core.ChallengeCalendar
import app.dailychallenge.core.ChallengeStore
import app.dailychallenge.core.ChallengeTime
import app.dailychallenge.core.DietState
import app.dailychallenge.core.ExtraSchedule
import app.dailychallenge.core.Habit
import app.dailychallenge.core.Target
import app.dailychallenge.core.TargetUnit
import app.dailychallenge.core.Targets
import app.dailychallenge.core.WaterTarget
import app.dailychallenge.core.WidgetAccountStore
import app.dailychallenge.core.WidgetState
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.time.ZoneId
import java.util.UUID

/**
 * The three widgets' Glance layouts on synthetic history in a temporary folder (never the app's
 * own): what each shows, what each control speaks and which tap or app link it carries.
 */
@RunWith(AndroidJUnit4::class)
class WidgetLayoutTest {
    private val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
    private val directory = File(context.cacheDir, "widget-test-${UUID.randomUUID()}")
    private val owner = UUID.randomUUID()
    private val zone = ZoneId.of("Europe/Jersey")
    private val now = ChallengeTime.parse("2026-10-09T14:00:00Z")

    @After fun cleanUp() { directory.deleteRecursively() }

    private fun state(targets: Targets = Targets.STANDARD, setUp: (ChallengeStore) -> Unit = {}): WidgetState.Ready {
        WidgetAccountStore(directory).publish(owner)
        val store = ChallengeStore(owner, directory)
        store.start(ChallengeCalendar(zone).addDays(now, -11), zone, targets, now)
        setUp(store)
        return WidgetState.load(directory, now) as WidgetState.Ready
    }

    private fun tap(state: WidgetState.Ready, kind: String, target: String = "") = hasRunCallbackClickAction<WidgetTapCallback>(
        actionParametersOf(
            WidgetTapCallback.Keys.kind to kind,
            WidgetTapCallback.Keys.target to target,
            WidgetTapCallback.Keys.generation to state.binding.generation.toString(),
            WidgetTapCallback.Keys.challenge to state.binding.challengeID.toString(),
        ))

    private fun opens(destination: Destination) = hasStartActivityClickAction(
        Intent(context, MainActivity::class.java).setAction("app.dailychallenge.android.OPEN_${destination.name}"))

    @Test
    fun waterShowsTheTotalWithPourAndUndo() = runGlanceAppWidgetUnitTest {
        val ready = state { store -> repeat(3) { store.record(Action.Pour(450), now, now) } }
        setContext(context)
        setAppWidgetSize(DpSize(160.dp, 200.dp))
        provideComposable { WidgetSurface(ready, Destination.TODAY) { WaterContent(it) } }
        onNode(hasText("1,350")).assertExists()
        onNode(hasContentDescriptionEqualTo("Water, 1,350 of 4,000 millilitres")).assertExists()
        onNode(hasContentDescriptionEqualTo("Add 450 ml")).assert(tap(ready, "pour"))
        onNode(hasContentDescriptionEqualTo("Undo latest pour")).assert(tap(ready, "undoPour"))
    }

    @Test
    fun undoIsDisabledWithoutAPourTodayAndTheGoalReadsAsExceeded() = runGlanceAppWidgetUnitTest {
        val empty = state()
        setContext(context)
        setAppWidgetSize(DpSize(300.dp, 160.dp))
        provideComposable { WidgetSurface(empty, Destination.TODAY) { WaterContent(it) } }
        onNode(hasContentDescriptionEqualTo("Undo latest pour, no pour today")).assert(hasNoClickAction())
        onNode(hasText("4,000 ml to go")).assertExists()
    }

    @Test
    fun overTheGoalReadsAsExceeded() = runGlanceAppWidgetUnitTest {
        val over = state { store -> store.record(Action.Pour(4_500), now, now) }
        setContext(context)
        setAppWidgetSize(DpSize(300.dp, 160.dp))
        provideComposable { WidgetSurface(over, Destination.TODAY) { WaterContent(it) } }
        onNode(hasContentDescriptionEqualTo("Water, 4,500 of 4,000 millilitres, goal exceeded")).assertExists()
        onNode(hasText("Goal met")).assertExists()
    }

    @Test
    fun requirementRingsSpeakTheirStateAndCarryTheirTap() = runGlanceAppWidgetUnitTest {
        val ready = state { store -> store.record(Action.SetHabit(Habit.WORKOUT, true), now, now) }
        setContext(context)
        setAppWidgetSize(DpSize(320.dp, 180.dp))
        provideComposable { WidgetSurface(ready, Destination.TODAY) { RequirementsContent(it) } }
        onNode(hasText("Day 12")).assertExists()
        onNode(hasContentDescriptionEqualTo("Workout, 45 minutes, home or gym, done")).assert(tap(ready, "habit", "workout"))
        onNode(hasContentDescriptionEqualTo("Walk, 45 minutes, pending")).assert(tap(ready, "habit", "walk"))
        onNode(hasContentDescriptionEqualTo("Bible, 10 pages, pending")).assert(tap(ready, "habit", "bibleReading"))
        onNode(hasContentDescriptionEqualTo("Clean diet, your own rules, pending")).assert(tap(ready, "diet"))
    }

    private val custom = Targets(WaterTarget(3_000, 330), Target("Gym", 45, TargetUnit.MINUTES), Target("Yoga", 30, TargetUnit.MINUTES, "yoga"),
        Target("No sugar"), Target("Audiobook", 20, TargetUnit.MINUTES, "headphones"))

    @Test
    fun requirementRingsShowTheDaysOwnGoals() = runGlanceAppWidgetUnitTest {
        val ready = state(custom) { store -> store.record(Action.SetHabit(Habit.WALK, true), now, now) }
        setContext(context)
        setAppWidgetSize(DpSize(320.dp, 180.dp))
        provideComposable { WidgetSurface(ready, Destination.TODAY) { RequirementsContent(it) } }
        onNode(hasText("YOGA")).assertExists()
        onNode(hasContentDescriptionEqualTo("Gym, 45 minutes, pending")).assert(tap(ready, "habit", "workout"))
        onNode(hasContentDescriptionEqualTo("Yoga, 30 minutes, done")).assert(tap(ready, "habit", "walk"))
        onNode(hasContentDescriptionEqualTo("Audiobook, 20 minutes, pending")).assert(tap(ready, "habit", "bibleReading"))
        onNode(hasContentDescriptionEqualTo("No sugar, your own rules, pending")).assert(tap(ready, "diet"))
    }

    @Test
    fun waterFollowsTheDaysGoalAndGlass() = runGlanceAppWidgetUnitTest {
        val ready = state(custom) { store -> store.record(Action.Pour(330), now, now) }
        setContext(context)
        setAppWidgetSize(DpSize(300.dp, 160.dp))
        provideComposable { WidgetSurface(ready, Destination.TODAY) { WaterContent(it) } }
        onNode(hasContentDescriptionEqualTo("Water, 330 of 3,000 millilitres")).assertExists()
        onNode(hasContentDescriptionEqualTo("Add 330 ml")).assert(tap(ready, "pour"))
        onNode(hasText("2,670 ml to go")).assertExists()
    }

    @Test
    fun aRepeatingExtraSaysHowItRepeats() = runGlanceAppWidgetUnitTest {
        val stretch = UUID.randomUUID()
        val ready = state { store ->
            store.record(Action.DefineExtra(stretch, "Stretch"), now, now)
            store.record(ExtraSchedule.Every(1).action(stretch), now, now)
        }
        setContext(context)
        setAppWidgetSize(DpSize(300.dp, 180.dp))
        provideComposable { WidgetSurface(ready, Destination.EXTRAS) { ExtrasContent(it) } }
        onNode(hasContentDescriptionEqualTo("Stretch, every day, pending")).assert(tap(ready, "extra", stretch.toString().uppercase()))
    }

    @Test
    fun aMissedDietOpensTheAppInsteadOfRecording() = runGlanceAppWidgetUnitTest {
        val missed = state { store -> store.record(Action.SetDiet(DietState.MISSED), now, now) }
        setContext(context)
        setAppWidgetSize(DpSize(320.dp, 180.dp))
        provideComposable { WidgetSurface(missed, Destination.TODAY) { RequirementsContent(it) } }
        onNode(hasContentDescriptionEqualTo("Clean diet, missed. Opens Daily Challenge to change it")).assert(opens(Destination.TODAY))
    }

    private fun tenExtras(store: ChallengeStore): List<UUID> = (1..10).map { index ->
        UUID.randomUUID().also { store.record(Action.DefineExtra(it, "Extra number $index"), now, now) }
    }

    @Test
    fun extrasShowWhatFitsWithALinkToTheRest() = runGlanceAppWidgetUnitTest {
        var ids = emptyList<UUID>()
        val ready = state { store -> ids = tenExtras(store); store.record(Action.SetExtra(ids[0], true), now, now) }
        setContext(context)
        setAppWidgetSize(DpSize(300.dp, 180.dp))
        provideComposable { WidgetSurface(ready, Destination.EXTRAS) { ExtrasContent(it) } }
        onNode(hasText("Extras · 1/10")).assertExists()
        onNode(hasContentDescriptionEqualTo("Extra number 1, done")).assert(tap(ready, "extra", ids[0].toString().uppercase()))
        onNode(hasContentDescriptionEqualTo("Open all 10 extras")).assert(opens(Destination.EXTRAS))
        // 180 dp: two 36 dp rows above the link.
        onAllNodes(hasContentDescription(", pending")).assertCountEquals(1)
    }

    @Test
    fun aTallExtrasWidgetShowsAllTen() = runGlanceAppWidgetUnitTest {
        val ready = state { store -> tenExtras(store) }
        setContext(context)
        setAppWidgetSize(DpSize(300.dp, 470.dp))
        provideComposable { WidgetSurface(ready, Destination.EXTRAS) { ExtrasContent(it) } }
        onAllNodes(hasContentDescription(", pending")).assertCountEquals(10)
        onNode(hasText("Open all")).assertDoesNotExist()
    }

    @Test
    fun largeTextShowsFewerExtrasAndKeepsTheLink() = runGlanceAppWidgetUnitTest {
        val ready = state { store -> tenExtras(store) }
        val large = context.createConfigurationContext(Configuration(context.resources.configuration).apply { fontScale = 1.3f })
        setContext(large)
        setAppWidgetSize(DpSize(300.dp, 470.dp))
        provideComposable { WidgetSurface(ready, Destination.EXTRAS) { ExtrasContent(it) } }
        onNode(hasText("Open all 10 extras")).assertExists()
        // Rows grow from 36 to 43 dp: eight fit above the link instead of all ten.
        onAllNodes(hasContentDescription(", pending")).assertCountEquals(8)
    }

    @Test
    fun emptyExtrasInviteYouToAddThem() = runGlanceAppWidgetUnitTest {
        val ready = state()
        setContext(context)
        setAppWidgetSize(DpSize(300.dp, 180.dp))
        provideComposable { WidgetSurface(ready, Destination.EXTRAS) { ExtrasContent(it) } }
        onNode(hasText("Add your own to-dos")).assertExists()
        onNode(hasContentDescription("Daily Challenge")).assertDoesNotExist()
    }

    @Test
    fun signedOutShowsOnlyACalmLineAndOpensTheApp() = runGlanceAppWidgetUnitTest {
        setContext(context)
        setAppWidgetSize(DpSize(300.dp, 180.dp))
        provideComposable { WidgetSurface(WidgetState.SignedOut, Destination.TODAY) { WaterContent(it) } }
        onNode(hasContentDescriptionEqualTo("Daily Challenge. Open Daily Challenge to sign in")).assertExists()
        onNode(hasText("ml")).assertDoesNotExist()
        onNode(opens(Destination.TODAY)).assert(hasClickAction())
    }
}

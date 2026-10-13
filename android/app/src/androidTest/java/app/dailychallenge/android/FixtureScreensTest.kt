package app.dailychallenge.android

import android.content.Intent
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasStateDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The real activity on the Debug-only fixture entry point: offline data in a temporary folder,
 * a fixed clock, no session, network, alarm or notification. Nothing here can reach an account.
 */
@RunWith(AndroidJUnit4::class)
class FixtureScreensTest {
    @get:Rule val compose = createEmptyComposeRule()
    private var scenario: ActivityScenario<MainActivity>? = null

    private fun launch(screen: String, vararg flags: String, extras: Map<String, String> = emptyMap()) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = Intent(context, MainActivity::class.java).putExtra("fixture", screen)
        flags.forEach { intent.putExtra(it, true) }
        extras.forEach { (key, value) -> intent.putExtra(key, value) }
        scenario = ActivityScenario.launch(intent)
        compose.waitForIdle()
    }

    @After fun close() { scenario?.close() }

    @Test fun signInNeedsEmailAndPassword() {
        launch("signIn")
        compose.onNodeWithTag("auth-title").assertIsDisplayed()
        compose.onNodeWithTag("auth-primary").assertIsNotEnabled()
        compose.onNodeWithTag("auth-email").performTextInput("sam@example.com")
        compose.onNodeWithTag("auth-password").performTextInput("not a real password 1")
        compose.onNodeWithTag("auth-primary").assertIsEnabled()
    }

    @Test fun createAccountShowsTheRulesAndCodeStepCountsDown() {
        launch("createAccount")
        compose.onNode(hasTestTag("auth-title") and hasText("Create account")).assertExists()
        compose.onNodeWithText("10+", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("auth-primary").assertIsNotEnabled()
        scenario?.close()
        launch("confirmCode")
        compose.onNodeWithTag("auth-notice").assertIsDisplayed()
        compose.onNodeWithText("42s").assertIsDisplayed()
    }

    @Test fun pourAddsToTheTotalAndUndoTakesItBack() {
        launch("today")
        compose.onNodeWithTag("water-total").assertExists()
        compose.onNode(hasTestTag("water-total") and hasContentDescription("2250 of 4,000 millilitres")).assertExists()
        compose.onNodeWithTag("water-add").performClick()
        compose.onNode(hasTestTag("water-total") and hasContentDescription("2700 of 4,000 millilitres")).assertExists()
        compose.onNodeWithTag("water-undo").performClick()
        compose.onNode(hasTestTag("water-total") and hasContentDescription("2250 of 4,000 millilitres")).assertExists()
    }

    @Test fun habitRingToggles() {
        launch("today")
        compose.onNode(hasTestTag("ring-walk") and hasStateDescription("Not complete")).performClick()
        compose.onNode(hasTestTag("ring-walk") and hasStateDescription("Complete")).assertExists()
    }

    @Test fun completingTheDayShowsTheBand() {
        launch("todayComplete")
        compose.onNodeWithText("All five complete!").assertIsDisplayed()
        compose.onNodeWithText("Day 12 counts toward your streak").assertIsDisplayed()
    }

    @Test fun pastDaysNeedEditThisDay() {
        launch("history")
        compose.onNodeWithTag("water-add").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("history-edit").performScrollTo().performClick()
        compose.onNodeWithTag("history-editing").assertExists()
        compose.onNodeWithTag("water-add").assertIsEnabled()
    }

    @Test fun extrasCarryOverAndCanBeAdded() {
        launch("todayExtras")
        // Two extras added two days ago are still open, so they carry over marked late.
        compose.onNode(hasContentDescription("Stretch, late")).performScrollTo().assertIsDisplayed()
        compose.onNode(hasContentDescription("Read a chapter, late")).assertExists()
        compose.onNodeWithTag("extras-manage").performScrollTo().performClick()
        compose.onNodeWithTag("extras-active-count").assertIsDisplayed()
        compose.onNodeWithTag("extras-new-title").performTextInput("Stretch for ten minutes")
        compose.onNodeWithTag("extras-add").performClick()
        // Listed in the sheet and, behind it, on Today's checklist (not late: added today).
        compose.onNode(hasContentDescription("Stretch for ten minutes")).assertExists()
        compose.onNodeWithTag("extras-active-count").assert(hasText("3/10 extras"))
    }

    @Test fun extrasCapExplainsTheLimit() {
        launch("extrasCap", "manageExtras")
        compose.onNodeWithTag("extras-cap").assertIsDisplayed()
    }

    @Test fun setupStartsTheChallenge() {
        launch("setup")
        compose.onNodeWithText("Your next 75 days").assertIsDisplayed()
        compose.onNodeWithTag("setup-start-challenge").performScrollTo().performClick()
        compose.onNodeWithTag("ring-water").assertIsDisplayed()
    }

    @Test fun setupAcceptsTheStandardFiveOrChosenGoals() {
        launch("setup")
        compose.onNode(hasTestTag("goal-water") and hasContentDescription("Water, 4,000 millilitres a day, 450 millilitre glass. Change"))
            .assertExists()
        compose.onNode(hasTestTag("goal-workout") and hasContentDescription("Workout, 45 minutes, home or gym. Change")).assertExists()
        compose.onNode(hasTestTag("goal-diet") and hasContentDescription("Clean diet, your own rules. Change")).assertExists()
        // The walk becomes yoga, the reading an audiobook, and water 3,000 ml in 330 ml glasses.
        compose.onNodeWithTag("goal-walk").performScrollTo().performClick()
        compose.onNodeWithTag("preset-Yoga").performClick()
        compose.onNode(hasTestTag("goal-preview") and hasContentDescription("Shows as Yoga, 30 minutes")).assertExists()
        compose.onNodeWithTag("goal-done").performClick()
        compose.onNode(hasTestTag("goal-walk") and hasContentDescription("Yoga, 30 minutes. Change")).assertExists()
        compose.onNodeWithTag("goal-bibleReading").performScrollTo().performClick()
        compose.onNodeWithTag("preset-Audiobook").performClick()
        compose.onNodeWithTag("goal-done").performClick()
        compose.onNodeWithTag("goal-water").performScrollTo().performClick()
        repeat(4) { compose.onNodeWithTag("water-goal-minus").performClick() }
        compose.onNodeWithTag("glass-330").performClick()
        compose.onNode(hasTestTag("water-goal-summary") and hasText("The + button adds 330 ml. About 10 glasses a day.")).assertExists()
        compose.onNodeWithTag("goal-done").performClick()
        compose.onNodeWithTag("setup-start-challenge").performScrollTo().performClick()
        compose.onNode(hasTestTag("ring-walk") and hasContentDescription("Yoga, 30 minutes")).assertExists()
        compose.onNode(hasTestTag("ring-bibleReading") and hasContentDescription("Audiobook, 20 minutes")).assertExists()
        compose.onNode(hasTestTag("water-total") and hasContentDescription("0 of 3,000 millilitres")).assertExists()
        compose.onNodeWithTag("water-add").performScrollTo().performClick()
        compose.onNode(hasTestTag("water-total") and hasContentDescription("330 of 3,000 millilitres")).assertExists()
    }

    @Test fun editorsEnforceTheLimits() {
        launch("setup", extras = mapOf("editGoal" to "water"))
        repeat(12) { compose.onNodeWithTag("water-goal-minus").performClick() }
        compose.onNodeWithTag("water-goal-minus").assertIsNotEnabled()
        compose.onNode(hasTestTag("water-goal") and hasContentDescription("Daily goal, 1,000 millilitres")).assertExists()
        compose.onNodeWithTag("glass-other").performClick()
        compose.onNodeWithTag("glass-other-amount").performTextReplacement("1200")
        compose.onNode(hasTestTag("water-goal-error") and hasContentDescription("Error: Enter a glass of 50 to 1,000 ml.")).assertExists()
        compose.onNodeWithTag("goal-done").assertIsNotEnabled()
        compose.onNodeWithTag("glass-750").performClick()
        compose.onNodeWithTag("goal-done").assertIsEnabled()
        compose.onNodeWithTag("goal-cancel").performClick()
        compose.onNodeWithTag("goal-workout").performScrollTo().performClick()
        compose.onNodeWithTag("goal-name").performTextReplacement("A name far beyond twenty")
        compose.onNode(hasTestTag("goal-name-help") and hasText("Use a name of 1 to 20 characters on one line.")).assertExists()
        compose.onNodeWithTag("goal-done").assertIsNotEnabled()
        compose.onNodeWithTag("goal-name").performTextReplacement("Rowing")
        compose.onNodeWithTag("goal-amount-field").performTextReplacement("301")
        compose.onNode(hasTestTag("goal-amount-error") and hasContentDescription("Error: Minutes: 5 to 300.")).assertExists()
        compose.onNodeWithTag("goal-done").assertIsNotEnabled()
        compose.onNodeWithTag("goal-amount-field").performTextReplacement("40")
        compose.onNodeWithTag("goal-done").performClick()
        compose.onNode(hasTestTag("goal-workout") and hasContentDescription("Rowing, 40 minutes. Change")).assertExists()
    }

    @Test fun dailyGoalsChangeFromTodayAndHistoryKeepsEarlierDays() {
        launch("account")
        compose.onNodeWithTag("account-goals").performScrollTo().performClick()
        compose.onNode(hasTestTag("goals-note") and hasText("Changes apply from today, Fri 9 Oct. Earlier days keep the goals they had."))
            .assertExists()
        compose.onNodeWithTag("goal-diet").performClick()
        compose.onNodeWithTag("preset-No sugar").performClick()
        compose.onNodeWithTag("goal-done").performClick()
        compose.onNode(hasTestTag("goal-diet") and hasContentDescription("No sugar, your own rules. Change")).assertExists()
        compose.onNodeWithTag("goals-done").performClick()
        compose.onNodeWithTag("tab-today").performClick()
        compose.onNode(hasTestTag("ring-diet") and hasContentDescription("No sugar, your own rules. Tap to cycle pending, clean and missed"))
            .assertExists()
        compose.onNodeWithTag("tab-history").performClick()
        compose.onNodeWithText("Diet renamed to No sugar").performScrollTo().assertIsDisplayed()
    }

    @Test fun historyShowsEachDaysOwnGoalsAndTheChange() {
        launch("historyGoals")
        compose.onNodeWithText("Walk changed to Yoga · 30 min").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Water goal changed to 3,000 ml, 330 ml glass").assertExists()
        compose.onNodeWithText("Workout changed to Gym · 45 min").assertExists()
        compose.onNode(hasTestTag("pill-walk") and hasContentDescription("Yoga, 30 minutes")).assertExists()
        scenario?.close()
        launch("historyBeforeGoals")
        compose.onNode(hasTestTag("pill-walk") and hasContentDescription("Walk, 45 minutes")).performScrollTo().assertExists()
        compose.onNode(hasContentDescription("2250 of 4,000 millilitres")).assertDoesNotExist()
        compose.onNode(hasContentDescription("4050 of 4,000 millilitres")).assertExists()
    }

    @Test fun anUnmigratedServerKeepsChangedGoalsOnThisPhoneAndSaysSo() {
        launch("goalsServerUpdate", "dailyGoals")
        compose.waitUntil(5_000) { compose.onAllNodes(hasTestTag("goals-server-update")).fetchSemanticsNodes().isNotEmpty() }
        compose.onNode(hasTestTag("goal-walk") and hasContentDescription("Yoga, 30 minutes. Change")).assertExists()
        compose.onNodeWithTag("goals-done").performClick()
        compose.onNodeWithTag("account-sync").assert(hasText("Can't reach the server, your entries are safe"))
        compose.onNodeWithText("The server needs the update for custom goals", substring = true).assertExists()
    }

    @Test fun repeatingExtrasShowOnTheirDaysAndAreNeverLate() {
        launch("todayRepeating")
        compose.onNode(hasContentDescription("Book dentist, late")).performScrollTo().assertIsDisplayed()
        compose.onNode(hasContentDescription("Stretch, every day") and hasStateDescription("Done")).assertExists()
        compose.onNode(hasContentDescription("Pack lunch, weekdays") and hasStateDescription("Not done")).assertExists()
        compose.onNode(hasContentDescription("Call family, Fridays") and hasStateDescription("Done")).assertExists()
        // Every 3 days from Wednesday: not today (Friday).
        compose.onNode(hasContentDescription("Water the plants", substring = true)).assertDoesNotExist()
        compose.onNodeWithTag("extras-count", useUnmergedTree = false).assert(hasContentDescription("Extras, 2 of 4 done"))
    }

    @Test fun customGoalsFromTheStartAndAnInMemoryServerReadAsSynced() {
        launch("todayComplete", "customGoals", "synced")
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Local only")).fetchSemanticsNodes().isEmpty() }
        compose.onNode(hasTestTag("water-total") and hasContentDescription("3300 of 3,000 millilitres")).assertExists()
        compose.onNodeWithText("All five complete!").assertExists()
        scenario?.close()
        launch("account", "customGoals", "synced")
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Up to date", substring = true)).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("not connected to the server", substring = true).assertDoesNotExist()
    }

    @Test fun manageExtrasChangesHowAnExtraRepeats() {
        launch("todayRepeating", "manageExtras", extras = mapOf("editExtra" to "Book dentist"))
        compose.onNodeWithTag("repeat-days").performClick()
        compose.onNodeWithTag("repeat-day-6").performClick()
        compose.onNodeWithTag("repeat-day-7").performClick()
        compose.onNodeWithText("Choose at least one day.").assertExists()
        compose.onNodeWithTag("extras-save").assertIsNotEnabled()
        compose.onNodeWithTag("repeat-day-5").performClick()
        compose.onNodeWithTag("extras-save").performClick()
        // In the sheet and, behind it, on Today's checklist: no longer late, since it repeats from today.
        compose.onAllNodes(hasContentDescription("Book dentist, Fridays")).assertCountEquals(2)
        // Added as a repeating extra from the start.
        compose.onNodeWithTag("extras-new-title").performTextInput("Floss")
        compose.onNodeWithTag("repeat-every").performClick()
        compose.onNodeWithTag("repeat-interval-plus").performClick()
        compose.onNodeWithTag("extras-add").performScrollTo().performClick()
        compose.onNode(hasContentDescription("Floss, Every 3 days")).assertExists()
    }

    @Test fun checkingWaitsForTheServer() {
        launch("checking")
        compose.onNodeWithText("Checking for your existing challenge").assertIsDisplayed()
    }

    @Test fun accountDeletionIsConfirmedTwiceThenSignsOut() {
        launch("account")
        compose.onNodeWithTag("account-email", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithTag("account-delete").performScrollTo().performClick()
        compose.onNodeWithTag("delete-account-continue").performScrollTo().performClick()
        compose.onNodeWithTag("delete-account-confirm").performClick()
        compose.waitUntil(5_000) { compose.onAllNodes(hasTestTag("auth-title")).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Your account and all its challenge history have been deleted.").assertIsDisplayed()
    }

    @Test fun failedDeletionKeepsEverything() {
        launch("account", "deleteAccountConfirm", "deletionFails")
        compose.waitUntil(5_000) { compose.onAllNodes(hasTestTag("delete-account-confirm")).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("delete-account-confirm").performClick()
        compose.waitUntil(5_000) { compose.onAllNodes(hasTestTag("delete-account-error")).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("delete-account-email").assertExists()
    }

    @Test fun signOutAsksFirst() {
        launch("account")
        compose.onNodeWithTag("account-sign-out").performScrollTo().performClick()
        compose.onNodeWithText("Sign out on this phone?").assertIsDisplayed()
    }

}

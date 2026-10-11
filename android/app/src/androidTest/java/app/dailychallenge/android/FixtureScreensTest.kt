package app.dailychallenge.android

import android.content.Intent
import androidx.compose.ui.test.assert
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

    private fun launch(screen: String, vararg flags: String) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = Intent(context, MainActivity::class.java).putExtra("fixture", screen)
        flags.forEach { intent.putExtra(it, true) }
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

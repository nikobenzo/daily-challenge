package app.dailychallenge.android.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import app.dailychallenge.android.AppGraph
import app.dailychallenge.android.Tab

/**
 * Signed out: the auth screens. Signed in: a navigation bar (Today, History, Account); Account
 * stays reachable before a challenge exists.
 */
@Composable
fun RootScreen(graph: AppGraph, visible: Boolean) {
    val auth = graph.auth
    auth.observe()
    graph.tracker.observe()
    LaunchedEffect(graph.fixture.showManagement) { if (graph.fixture.showManagement) graph.manageExtrasRequested = true }
    when {
        !auth.configurationReady -> PhoneScreen {
            PhoneHeader()
            NoticeCard(Icons.Outlined.Settings, "Configuration unavailable", auth.errorMessage ?: "This build cannot reach the server.")
        }
        auth.ownerID == null -> AuthScreen(graph)
        else -> Tabs(graph, visible)
    }
    if (graph.manageExtrasRequested && auth.ownerID != null && graph.tracker.challenge != null) {
        ManageExtrasSheet(graph.tracker) { graph.manageExtrasRequested = false }
    }
}

@Composable
private fun Tabs(graph: AppGraph, visible: Boolean) {
    graph.tracker.observe()

    val tracker = graph.tracker
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).consumeWindowInsets(WindowInsets.navigationBars)) {
            when (graph.tab) {
                Tab.TODAY -> TodayTab(graph, visible)
                Tab.HISTORY -> HistoryTab(graph, visible)
                Tab.ACCOUNT -> AccountScreen(graph)
            }
        }
        val colors = NavigationBarItemDefaults.colors(selectedIconColor = P.accentText, selectedTextColor = P.accentText,
            indicatorColor = P.accentTint, unselectedIconColor = P.textSecondary, unselectedTextColor = P.textSecondary)
        NavigationBar(containerColor = P.solidGlass, tonalElevation = androidx.compose.ui.unit.Dp(0f)) {
            listOf(
                Triple(Tab.TODAY, "Today", Icons.Filled.WbSunny to Icons.Outlined.WbSunny),
                Triple(Tab.HISTORY, "History", Icons.Filled.CalendarMonth to Icons.Outlined.CalendarMonth),
                Triple(Tab.ACCOUNT, "Account", Icons.Filled.Person to Icons.Outlined.Person),
            ).forEach { (tab, label, icons) ->
                val selected = graph.tab == tab
                NavigationBarItem(selected, onClick = {
                    if (tab == Tab.TODAY) tracker.showToday()
                    if (tab == Tab.HISTORY && graph.tab != Tab.HISTORY) tracker.selectHistoryDay(tracker.today)
                    graph.tab = tab
                }, icon = { Icon(if (selected) icons.first else icons.second, null) }, label = { Text(label) }, colors = colors,
                    modifier = Modifier.testTag("tab-${label.lowercase()}"))
            }
        }
    }
}

/**
 * Today, or what stands in for it before a challenge: setup, the server check, or an
 * unreadable local history (never reset).
 */
@Composable
private fun TodayTab(graph: AppGraph, visible: Boolean) {
    graph.tracker.observe()

    val tracker = graph.tracker
    when {
        tracker.store == null -> PhoneScreen {
            PhoneHeader()
            NoticeCard(Icons.Outlined.WarningAmber, "History unavailable", tracker.errorMessage ?: "Your saved data has not been reset.") {
                TintedPill("Try again", tracker::reload)
            }
        }
        tracker.challenge == null -> if (tracker.canStartChallenge) SetupScreen(tracker) else CheckingScreen(tracker)
        else -> TodayScreen(graph, visible)
    }
}

@Composable
private fun HistoryTab(graph: AppGraph, visible: Boolean) {
    graph.tracker.observe()

    val tracker = graph.tracker
    when {
        tracker.store == null -> TodayTab(graph, visible)
        tracker.challenge == null -> PhoneScreen {
            PhoneHeader("History")
            NoticeCard(Icons.Outlined.CalendarMonth, "No history yet", "Your calendar starts once your challenge does. Set it up on Today.") {
                TintedPill("Go to Today", { graph.tab = Tab.TODAY })
            }
        }
        else -> HistoryScreen(tracker)
    }
}


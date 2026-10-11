package app.dailychallenge.android.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Contrast
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material.icons.outlined.PersonOff
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import app.dailychallenge.android.AppGraph
import app.dailychallenge.android.BuildConfig
import app.dailychallenge.core.ChallengeDates
import app.dailychallenge.core.DeviceWording
import app.dailychallenge.core.SyncState
import app.dailychallenge.core.WaterReminderController
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.ZoneId

/**
 * Account: who is signed in and the challenge's progress, sync, this phone's water reminders
 * and appearance, extras, sign out and account deletion. Reminders and appearance stay on this phone.
 */
@Composable
fun AccountScreen(graph: AppGraph) {
    val auth = graph.auth
    val tracker = graph.tracker
    auth.observe()
    tracker.observe()
    val scope = rememberCoroutineScope()
    var confirmingSignOut by rememberSaveable { mutableStateOf(false) }
    var deleting by rememberSaveable { mutableStateOf(graph.fixture.showDeletion) }
    var signOutError by remember { mutableStateOf<String?>(null) }

    PhoneScreen {
        PhoneHeader("Account")
        GlassCard {
            You(graph, Modifier.padding(horizontal = Size.sectionHorizontal, vertical = Size.sectionVertical))
            Hairline()
            SyncSection(graph, Modifier.padding(horizontal = Size.sectionHorizontal, vertical = 12.dp))
        }
        GlassCard {
            Column(Modifier.padding(horizontal = Size.sectionHorizontal, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                graph.reminders?.let { ReminderSettings(graph, it) }
                Hairline(Modifier.padding(vertical = 6.dp))
                SettingRow(Icons.Filled.Contrast, "Appearance")
                Segmented(app.dailychallenge.android.Appearance.entries.map { it to it.label }, graph.appearance, graph::chooseAppearance)
                Hairline(Modifier.padding(vertical = 6.dp))
                val extras = tracker.activeExtras.size
                SettingRow(Icons.Filled.Checklist, "Extras",
                    Modifier.clickable(enabled = tracker.challenge != null, role = Role.Button) { graph.manageExtrasRequested = true }
                        .semantics(mergeDescendants = true) { contentDescription = "Manage extras, $extras of 10" }
                        .testTag("account-extras")) {
                    Text("$extras/10", style = Type.field, color = P.textSecondary)
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = P.textTertiary)
                }
            }
        }
        GlassCard {
            Column(Modifier.padding(horizontal = Size.sectionHorizontal, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                SettingRow(Icons.AutoMirrored.Filled.Logout, "Sign out on this phone",
                    Modifier.clickable(enabled = !auth.isBusy, role = Role.Button) { confirmingSignOut = true }.testTag("account-sign-out"),
                    tint = P.danger) {
                    if (auth.isBusy && !deleting) CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                }
                signOutError?.let { FieldError("Couldn't sign out. $it") }
                Hairline(Modifier.padding(vertical = 6.dp))
                SettingRow(Icons.Outlined.Delete, "Delete account",
                    Modifier.clickable(enabled = !auth.isBusy && auth.accountDeletion != null, role = Role.Button) { deleting = true }
                        .testTag("account-delete"), tint = P.danger) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = P.textTertiary)
                }
                Hairline(Modifier.padding(vertical = 6.dp))
                SettingRow(Icons.Outlined.Info, "Version", Modifier.semantics(mergeDescendants = true) {}) {
                    Text("${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", style = Type.field.copy(fontFeatureSettings = "tnum"),
                        color = P.textSecondary)
                }
            }
        }
    }

    if (confirmingSignOut) {
        AlertDialog(
            onDismissRequest = { confirmingSignOut = false },
            title = { Text("Sign out on this phone?") },
            text = {
                Text("Your entries stay on the server and on your other devices. Entries not yet synced stay on this phone until you sign in again.")
            },
            confirmButton = {
                TextButton({
                    confirmingSignOut = false
                    scope.launch {
                        auth.signOut()
                        signOutError = if (auth.ownerID != null) auth.errorMessage else null
                    }
                }, modifier = Modifier.testTag("account-sign-out-confirm")) { Text("Sign out", color = P.danger) }
            },
            dismissButton = { TextButton({ confirmingSignOut = false }) { Text("Cancel") } },
            containerColor = P.solidGlass, titleContentColor = P.textPrimary, textContentColor = P.textSecondary,
        )
    }
    if (deleting) DeleteAccountSheet(graph) { deleting = false }
}

@Composable
private fun You(graph: AppGraph, modifier: Modifier) {
    graph.auth.observe()
    graph.tracker.observe()

    val auth = graph.auth
    val tracker = graph.tracker
    val email = auth.signedInEmail
    val initial = email?.firstOrNull { it.isLetter() }?.uppercase() ?: "?"
    val challenge = tracker.challenge
    // "Day 12 of 75 · started Sat 27 Sep", worded as on the Mac and iPhone.
    val progress = if (challenge == null) "Challenge not started yet" else {
        val started = "started ${tracker.dates.label(challenge.startDate, "EEE d MMM")}"
        val day = tracker.dayNumber
        if (day <= 75) "Day $day of 75 · $started"
        else "Day $day" + (if ((tracker.streaks?.best ?: 0) >= 75) " · 75 reached" else "") + " · $started"
    }
    Row(modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.size(52.dp).shadow(8.dp, CircleShape, spotColor = P.primaryShadow).clip(CircleShape).background(P.appMarkGradient),
            contentAlignment = Alignment.Center) {
            Text(initial, style = Type.streak, color = Color.White)
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(email ?: "Signed in", style = Type.pill, color = P.textPrimary, maxLines = 1, overflow = TextOverflow.MiddleEllipsis,
                modifier = Modifier.testTag("account-email"))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.CalendarMonth, null, tint = P.textSecondary, modifier = Modifier.size(14.dp))
                Text(progress, style = Type.caption, color = P.textSecondary)
            }
        }
    }
}

@Composable
private fun SyncSection(graph: AppGraph, modifier: Modifier) {
    graph.tracker.observe()

    val tracker = graph.tracker
    val scope = rememberCoroutineScope()
    val state = tracker.syncState
    val wording = DeviceWording.android
    val synced = state is SyncState.Synced && !state.clockWarning
    val pattern = if (android.text.format.DateFormat.is24HourFormat(LocalContext.current)) "HH:mm" else "h:mm a"
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(SyncWords.icon(state), null, tint = if (synced) P.done else if (state is SyncState.Unavailable) P.amber else P.textPrimary,
                modifier = Modifier.size(22.dp))
            Text(state.plainText(wording) { tracker.dates.label(it, pattern) }, style = Type.field, color = P.textPrimary,
                modifier = Modifier.weight(1f).testTag("account-sync"))
            if (tracker.syncActive) {
                RoundIconButton(Icons.Filled.Sync, "Sync now", { scope.launch { tracker.sync(force = true) } }, enabled = !tracker.isSyncing,
                    size = 40.dp)
            }
        }
        if (state is SyncState.Unavailable) {
            val pending = state.pending
            Text("$pending change${if (pending == 1) "" else "s"} waiting on this phone. Details: ${state.error}", style = Type.caption,
                color = P.amberText)
        }
        state.clockWarningText(wording)?.let { warning ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Outlined.Schedule, null, tint = P.amberText, modifier = Modifier.size(15.dp))
                Text(warning, style = Type.caption, color = P.amberText)
            }
        }
        tracker.skippedNotice?.let { skipped ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Outlined.WarningAmber, null, tint = P.textSecondary, modifier = Modifier.size(15.dp))
                Text(skipped, style = Type.caption, color = P.textSecondary)
            }
        }
    }
}

private fun minuteLabel(minute: Int, twentyFour: Boolean): String {
    val hour = minute / 60
    val min = minute % 60
    return if (twentyFour) "%02d:%02d".format(hour, min)
    else "%d:%02d %s".format(if (hour % 12 == 0) 12 else hour % 12, min, if (hour < 12) "AM" else "PM")
}

fun reminderDetails(zone: ZoneId): String =
    "Times are ${ChallengeDates.city(zone)} time, your challenge's time zone. Reminders stop for the day at 4,000 ml; " +
        "a goal met on another device stops them here once this phone syncs. This setting stays on this phone."

/**
 * Water reminders on this phone: on or off, interval and the daily window, in the challenge's
 * zone. Notification permission is asked for only when reminders are turned on.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReminderSettings(graph: AppGraph, model: WaterReminderController) {
    @Suppress("UNUSED_VARIABLE") val tick = graph.reminderChanges
    val context = LocalContext.current
    val twentyFour = android.text.format.DateFormat.is24HourFormat(context)
    val settings = model.settings
    var editing by remember { mutableStateOf<String?>(null) }
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        graph.markNotificationsAsked()
        model.update(model.settings.copy(enabled = true))
    }
    fun setEnabled(on: Boolean) {
        if (on && !graph.isFixture && Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            request.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            model.update(settings.copy(enabled = on))
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(role = Role.Switch) { setEnabled(!settings.enabled) }
            .semantics(mergeDescendants = true) { contentDescription = "Water reminders. ${reminderDetails(model.zone)}" }
            .testTag("reminders-toggle"),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Outlined.NotificationsNone, null, tint = P.textPrimary, modifier = Modifier.size(22.dp))
            Text("Water reminders", style = Type.rowLabel, color = P.textPrimary, modifier = Modifier.weight(1f))
            Switch(settings.enabled, null, colors = SwitchDefaults.colors(checkedTrackColor = P.toggleOn, uncheckedTrackColor = P.toggleOff,
                uncheckedBorderColor = Color.Transparent, uncheckedThumbColor = Color.White, checkedThumbColor = Color.White))
        }
        if (settings.enabled) {
            Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { stateDescription = "Every ${settings.intervalMinutes} minutes" },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Every ${settings.intervalMinutes} min", style = Type.field.copy(fontFeatureSettings = "tnum"), color = P.textPrimary,
                    modifier = Modifier.weight(1f))
                RoundIconButton(Icons.Filled.Remove, "Shorter interval", {
                    model.update(settings.copy(intervalMinutes = settings.intervalMinutes - 15))
                }, enabled = settings.intervalMinutes > 15, size = 36.dp)
                RoundIconButton(Icons.Filled.Add, "Longer interval", {
                    model.update(settings.copy(intervalMinutes = settings.intervalMinutes + 15))
                }, enabled = settings.intervalMinutes < 240, size = 36.dp)
            }
            listOf("From" to settings.startMinute, "Until" to settings.endMinute).forEach { (label, minute) ->
                Row(Modifier.fillMaxWidth().heightIn(min = 40.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(label, style = Type.field, color = P.textPrimary, modifier = Modifier.weight(1f))
                    TintedPill(minuteLabel(minute, twentyFour), { editing = label }, height = 34.dp,
                        modifier = Modifier.semantics { contentDescription = "$label ${minuteLabel(minute, twentyFour)}" })
                }
            }
        }
        Text(model.status, style = Type.caption, color = P.textTertiary, modifier = Modifier.testTag("reminders-status"))
        Text(reminderDetails(model.zone), style = Type.caption, color = P.textTertiary)
        model.errorMessage?.let { FieldError(it) }
    }
    editing?.let { label ->
        val initial = if (label == "From") settings.startMinute else settings.endMinute
        val picker = rememberTimePickerState(initial / 60, initial % 60, twentyFour)
        AlertDialog(
            onDismissRequest = { editing = null },
            title = { Text(if (label == "From") "Reminders from" else "Reminders until") },
            text = {
                TimePicker(picker, colors = TimePickerDefaults.colors(clockDialColor = P.controlFill, selectorColor = P.primaryBottom,
                    timeSelectorSelectedContainerColor = P.accentTint, timeSelectorUnselectedContainerColor = P.controlFill,
                    timeSelectorSelectedContentColor = P.textPrimary, timeSelectorUnselectedContentColor = P.textPrimary,
                    periodSelectorSelectedContainerColor = P.accentTint, clockDialUnselectedContentColor = P.textPrimary,
                    clockDialSelectedContentColor = Color.White))
            },
            confirmButton = {
                TextButton({
                    val value = picker.hour * 60 + picker.minute
                    model.update(if (label == "From") settings.copy(startMinute = value) else settings.copy(endMinute = value))
                    editing = null
                }) { Text("Done") }
            },
            dismissButton = { TextButton({ editing = null }) { Text("Cancel") } },
            containerColor = P.solidGlass, titleContentColor = P.textPrimary, textContentColor = P.textPrimary,
        )
    }
}

/**
 * Delete account, step one of two: what is deleted and where, before the final dialog. Nothing
 * is deleted anywhere unless the server confirms; a failure keeps the account, this phone's
 * session and every local entry, and says so.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DeleteAccountSheet(graph: AppGraph, onDismiss: () -> Unit) {
    val auth = graph.auth
    auth.observe()
    val scope = rememberCoroutineScope()
    var confirming by rememberSaveable { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    val email = auth.signedInEmail ?: "This account"
    val pending = graph.tracker.store?.pendingCount ?: 0
    val unsynced = when (pending) {
        0 -> "including anything not yet synced"
        1 -> "including 1 change not yet synced"
        else -> "including $pending changes not yet synced"
    }
    LaunchedEffect(Unit) {
        if (graph.fixture.showDeletionConfirmation) { delay(600); confirming = true }
    }
    AppSheet(onDismiss, dismissible = !auth.isBusy) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onDismiss, enabled = !auth.isBusy) { Text("Cancel", style = Type.pill, color = P.accentText) }
                Text("Delete account", style = Type.appName, color = P.textPrimary, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                Spacer(Modifier.size(72.dp, 1.dp))
            }
            GlassCard {
                Column(Modifier.padding(Size.sectionHorizontal), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Box(Modifier.size(60.dp).clip(CircleShape).background(P.dangerTint), contentAlignment = Alignment.Center) {
                            Icon(Icons.Outlined.Delete, null, tint = P.danger, modifier = Modifier.size(28.dp))
                        }
                    }
                    Text("Delete your account?", style = Type.screenTitle, color = P.textPrimary, textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().semantics { heading() })
                    Text(email, style = Type.field, color = P.textSecondary, textAlign = TextAlign.Center, maxLines = 1,
                        overflow = TextOverflow.MiddleEllipsis, modifier = Modifier.fillMaxWidth().testTag("delete-account-email"))
                    Point(Icons.Outlined.PersonOff, "Your account is deleted. You can't sign in to it again.")
                    Point(Icons.Outlined.CloudOff, "All your synced challenge history (every day, pour, habit, diet mark and extra) " +
                        "is permanently deleted from the server, for every device.")
                    Point(Icons.Outlined.PhoneAndroid, "This phone's copy is removed now, $unsynced.")
                    Point(Icons.Outlined.Devices, "Your other devices can no longer sync it and are signed out.")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Warning, null, tint = P.danger, modifier = Modifier.size(18.dp))
                        Text("This can't be undone.", style = Type.rowLabel, color = P.danger)
                    }
                    failure?.let { FieldError(it, Modifier.testTag("delete-account-error")) }
                    TintedPill(if (auth.isBusy) "Deleting account…" else "Delete account…", { failure = null; confirming = true },
                        Modifier.testTag("delete-account-continue"), enabled = !auth.isBusy, fill = P.dangerTint, foreground = P.danger,
                        expands = true, busy = auth.isBusy)
                    TintedPill("Keep my account", onDismiss, enabled = !auth.isBusy, expands = true)
                }
            }
        }
    }
    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text("Delete your account permanently?") },
            text = { Text("$email and all its challenge history will be deleted from the server and from this phone. This can't be undone.") },
            confirmButton = {
                TextButton({
                    confirming = false
                    scope.launch { if (graph.deleteAccount()) onDismiss() else failure = auth.errorMessage }
                }, modifier = Modifier.testTag("delete-account-confirm")) { Text("Delete account", color = P.danger) }
            },
            dismissButton = { TextButton({ confirming = false }) { Text("Cancel") } },
            containerColor = P.solidGlass, titleContentColor = P.textPrimary, textContentColor = P.textSecondary,
        )
    }
}

@Composable
private fun Point(icon: ImageVector, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, null, tint = P.textSecondary, modifier = Modifier.size(22.dp))
        Text(text, style = Type.field, color = P.textPrimary)
    }
}

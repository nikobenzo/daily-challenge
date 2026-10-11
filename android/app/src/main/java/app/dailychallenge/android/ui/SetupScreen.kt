package app.dailychallenge.android.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.automirrored.outlined.DirectionsWalk
import androidx.compose.material.icons.outlined.Eco
import androidx.compose.material.icons.outlined.FitnessCenter
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.dailychallenge.core.Challenge
import app.dailychallenge.core.ChallengeCalendar
import app.dailychallenge.core.ChallengeDates
import app.dailychallenge.core.TimeZoneChoices
import app.dailychallenge.core.Tracker
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

/** The phone's zone if it is one every device spells alike, otherwise GMT. */
fun deviceZone(): ZoneId = Challenge.canonicalZone(ZoneId.systemDefault().id) ?: ZoneId.of("GMT")

/** Every canonical location zone Android knows, as Apple's Foundation lists them. */
val zoneChoices: TimeZoneChoices by lazy {
    TimeZoneChoices(android.icu.util.TimeZone.getAvailableIDs(android.icu.util.TimeZone.SystemTimeZoneType.CANONICAL_LOCATION, null, null))
}

/**
 * Shown only after the server confirmed this account has no challenge yet (an existing one is
 * adopted by sync instead). Start date and zone cannot change once started.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SetupScreen(tracker: Tracker) {
    tracker.observe()
    var zoneID by rememberSaveable { mutableStateOf(deviceZone().id) }
    val zone = ZoneId.of(zoneID)
    val calendar = ChallengeCalendar(zone)
    val today = calendar.localDate(tracker.now)
    var start by rememberSaveable { mutableStateOf(today.toString()) }
    val startDate = LocalDate.parse(start).let { if (it > today) today else it }
    var choosingDate by rememberSaveable { mutableStateOf(false) }
    var choosingZone by rememberSaveable { mutableStateOf(false) }

    PhoneScreen {
        PhoneHeader { SyncChip(tracker) }
        GlassCard {
            Column(Modifier.fillMaxWidth().padding(top = 24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Your next 75 days", style = Type.screenTitle, color = P.textPrimary, modifier = Modifier.semantics { heading() })
                Text("Every day, midnight to midnight, all five.", style = Type.link, color = P.textSecondary)
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 16.dp)) {
                Requirement(Icons.Filled.WaterDrop, "4,000 ml", "4 litres of water", P.water, Modifier.weight(1f))
                Requirement(Icons.Outlined.FitnessCenter, "45 min", "45-minute workout, home or gym", P.textPrimary, Modifier.weight(1f))
                Requirement(Icons.AutoMirrored.Outlined.DirectionsWalk, "45 min", "45-minute walk", P.textPrimary, Modifier.weight(1f))
                Requirement(Icons.Outlined.Eco, "Clean diet", "Clean diet, your own rules", P.textPrimary, Modifier.weight(1f))
                Requirement(Icons.AutoMirrored.Outlined.MenuBook, "10 pages", "10 Bible pages", P.textPrimary, Modifier.weight(1f))
            }
            Hairline()
            Column(Modifier.padding(horizontal = Size.sectionHorizontal)) {
                val dateLabel = startDate.format(DateTimeFormatter.ofPattern("EEE d MMM yyyy", Locale.getDefault()))
                SettingRow(Icons.Filled.CalendarMonth, "Start",
                    Modifier.heightIn(min = 52.dp).clickable(role = Role.Button) { choosingDate = true }
                        .semantics(mergeDescendants = true) { contentDescription = "Start date, $dateLabel" }.testTag("setup-start")) {
                    Text(dateLabel, style = Type.field, color = P.textSecondary)
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = P.textTertiary)
                }
                Hairline()
                val zoneTitle = TimeZoneChoices.title(zone, tracker.now)
                SettingRow(Icons.Filled.Public, "Time zone",
                    Modifier.heightIn(min = 52.dp).clickable(role = Role.Button) { choosingZone = true }
                        .semantics(mergeDescendants = true) {
                            contentDescription = "Time zone, $zoneTitle. The city whose midnight starts each challenge day"
                        }.testTag("setup-zone")) {
                    Text(zoneTitle, style = Type.field, color = P.textSecondary, maxLines = 1)
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = P.textTertiary)
                }
            }
            Hairline()
            PrimaryPill("Start challenge", { tracker.startChallenge(startDate, zone) },
                Modifier.padding(horizontal = Size.sectionHorizontal, vertical = 16.dp).testTag("setup-start-challenge"),
                icon = Icons.Filled.PlayArrow, height = Size.largePill, style = Type.appName)
        }
        ErrorBanner(tracker)
        Text("Days follow ${zone.id}, midnight to midnight, including daylight saving. " +
            "The start date and time zone can't be changed after you start. " +
            "Closed unfinished days break the streak. Tracking continues beyond 75. " +
            "Use the same account on your other devices: activity saves on this phone first, then syncs.",
            style = Type.caption, color = P.textSecondary, modifier = Modifier.padding(horizontal = 4.dp))
    }

    if (choosingDate) {
        // The picker works in UTC midnights; each one stands for a calendar date.
        fun millis(date: LocalDate) = date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        val latest = millis(today)
        val state = rememberDatePickerState(initialSelectedDateMillis = millis(startDate),
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis <= latest
                override fun isSelectableYear(year: Int) = year <= today.year
            })
        DatePickerDialog(
            onDismissRequest = { choosingDate = false },
            confirmButton = {
                TextButton({
                    state.selectedDateMillis?.let { start = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString() }
                    choosingDate = false
                }) { Text("Done") }
            },
            dismissButton = { TextButton({ choosingDate = false }) { Text("Cancel") } },
            colors = DatePickerDefaults.colors(containerColor = P.solidGlass),
        ) {
            DatePicker(state, colors = DatePickerDefaults.colors(containerColor = P.solidGlass, selectedDayContainerColor = P.primaryBottom,
                todayDateBorderColor = P.water, todayContentColor = P.accentText, titleContentColor = P.textSecondary,
                headlineContentColor = P.textPrimary, dayContentColor = P.textPrimary, weekdayContentColor = P.textSecondary,
                disabledDayContentColor = P.futureDay, yearContentColor = P.textPrimary, selectedYearContainerColor = P.primaryBottom,
                navigationContentColor = P.textPrimary, subheadContentColor = P.textSecondary))
        }
    }
    if (choosingZone) {
        TimeZoneSheet(zone, tracker.now, { zoneID = it.id; choosingZone = false }) { choosingZone = false }
    }
}

@Composable
private fun Requirement(icon: ImageVector, label: String, detail: String, tint: Color, modifier: Modifier) {
    val track = P.ringTrack
    Column(modifier.semantics(mergeDescendants = true) { contentDescription = detail }, horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(56.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize().padding(Size.ringStroke / 2)) { drawCircle(track, style = Stroke(Size.ringStroke.toPx())) }
            Icon(icon, null, tint = tint, modifier = Modifier.size(20.dp))
        }
        Eyebrow(label, P.textSecondary, Type.ringLabel)
    }
}

/** Searchable by city, region or zone name, grouped by region, with this phone's zone first. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimeZoneSheet(selection: ZoneId, now: Double, onSelect: (ZoneId) -> Unit, onDismiss: () -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val groups = remember(query) { zoneChoices.groups(query) }
    AppSheet(onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Time zone", style = Type.appName, color = P.textPrimary, modifier = Modifier.weight(1f).semantics { heading() })
                TextButton(onDismiss) { Text("Cancel", color = P.accentText) }
            }
            DesignField(query, { query = it }, "Search for your city", Icons.Filled.Search, testTag = "zone-search")
            if (groups.isEmpty()) {
                Column(Modifier.fillMaxWidth().padding(vertical = 32.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.Public, null, tint = P.textTertiary, modifier = Modifier.size(32.dp))
                    Text("No matching city", style = Type.rowLabel, color = P.textPrimary)
                    Text("Try a nearby larger city in the same time zone.", style = Type.caption, color = P.textSecondary, textAlign = TextAlign.Center)
                }
            }
            LazyColumn(Modifier.fillMaxWidth().weight(1f, fill = false)) {
                if (query.isEmpty()) {
                    item { SectionTitle("This phone") }
                    item { ZoneRow(deviceZone(), now, selection, onSelect) }
                }
                groups.forEach { group ->
                    item(key = "region-${group.region}") { SectionTitle(group.region) }
                    items(group.zones, key = { it.id }) { ZoneRow(it, now, selection, onSelect) }
                }
            }
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Eyebrow(text, P.textSecondary, modifier = Modifier.padding(top = 16.dp, bottom = 6.dp))
}

@Composable
private fun ZoneRow(zone: ZoneId, now: Double, selection: ZoneId, onSelect: (ZoneId) -> Unit) {
    val selected = zone.id == selection.id
    val offset = ChallengeDates.offset(zone, now)
    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Button) { onSelect(zone) }
        .semantics(mergeDescendants = true) { contentDescription = "${ChallengeDates.city(zone)}, ${zone.id}, $offset"; this.selected = selected },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f)) {
            Text(ChallengeDates.city(zone), style = Type.field, color = P.textPrimary)
            Text(zone.id, style = Type.caption, color = P.textSecondary)
        }
        Text(offset, style = Type.caption.copy(fontFeatureSettings = "tnum"), color = P.textSecondary)
        Box(Modifier.size(18.dp)) { if (selected) Icon(Icons.Filled.Check, null, tint = P.accentText, modifier = Modifier.size(18.dp)) }
    }
}

/** Setup waits for a successful server check, so an existing challenge is adopted, never duplicated. */
@Composable
fun CheckingScreen(tracker: Tracker) {
    tracker.observe()
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    PhoneScreen {
        PhoneHeader { SyncChip(tracker) }
        NoticeCard(Icons.Filled.CloudDownload, "Checking for your existing challenge",
            "Setup needs a successful server check. Another of your devices may already have a challenge, and this phone will use it.") {
            TintedPill("Check again", { scope.launch { tracker.sync(force = true) } }, icon = Icons.Filled.Refresh, enabled = !tracker.isSyncing,
                busy = tracker.isSyncing)
        }
        tracker.syncError?.let { Text(it, style = Type.caption, color = P.textSecondary, modifier = Modifier.fillMaxWidth()) }
    }
}


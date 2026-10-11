package app.dailychallenge.android.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.outlined.Archive
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.automirrored.outlined.Label
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import app.dailychallenge.android.AppGraph
import app.dailychallenge.core.Challenge
import app.dailychallenge.core.Extra
import app.dailychallenge.core.Tracker
import java.util.UUID

/** Optional to-dos that carry over until done; their count comes from the selected day's summary. */
@Composable
fun ExtrasSection(graph: AppGraph) {
    val tracker = graph.tracker
    tracker.observe()
    Column(Modifier.padding(horizontal = Size.sectionHorizontal, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if ((tracker.summary?.extrasTotal ?: 0) == 0) {
            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(role = Role.Button) { graph.manageExtrasRequested = true }
                .testTag("extras-empty"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.Checklist, null, tint = P.textSecondary, modifier = Modifier.size(20.dp))
                Text("Extras · Add your own to-dos", style = Type.field, color = P.textSecondary)
            }
        } else {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                ExtrasHeading(tracker, Modifier.weight(1f))
                RoundIconButton(Icons.Outlined.EditNote, "Manage extras", { graph.manageExtrasRequested = true }, size = 44.dp,
                    modifier = Modifier.testTag("extras-manage"))
            }
            ExtrasChecklist(tracker)
        }
    }
}

@Composable
fun ExtrasHeading(tracker: Tracker, modifier: Modifier = Modifier) {
    tracker.observe()

    val done = tracker.summary?.extrasDone ?: 0
    val total = tracker.summary?.extrasTotal ?: 0
    Row(modifier.semantics(mergeDescendants = true) { contentDescription = "Extras, $done of $total done"; heading() }.testTag("extras-count"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Filled.Checklist, null, tint = P.textSecondary, modifier = Modifier.size(20.dp))
        Text("Extras · $done/$total", style = Type.rowLabel, color = P.textSecondary)
    }
}

/**
 * The selected day's extras: carried-over ones marked "Late", completed ones gone from later
 * days, and extras archived after that day.
 */
@Composable
fun ExtrasChecklist(tracker: Tracker) {
    tracker.observe()

    val summary = tracker.summary ?: return
    Column {
        summary.extras.forEach { extra ->
            val done = extra.id in summary.completedExtras
            val late = summary.isLate(extra)
            Row(
                Modifier.fillMaxWidth().heightIn(min = 44.dp)
                    .clickable(enabled = tracker.canEdit, role = Role.Checkbox) { tracker.toggleExtra(extra.id) }
                    .padding(vertical = 4.dp)
                    .semantics(mergeDescendants = true) {
                        contentDescription = if (late) "${extra.title}, late" else extra.title
                        stateDescription = if (done) "Done" else "Not done"
                    }
                    .testTag("extra-${Challenge.uuidString(extra.id)}"),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                TickCircle(done)
                Text(extra.title, style = Type.field, color = if (done) P.textSecondary else P.textPrimary, modifier = Modifier.weight(1f, fill = false))
                if (late) LateMarker()
                Spacer(Modifier.weight(1f))
            }
        }
    }
}

private fun titleHelp(title: String): Pair<String, Boolean> {
    val invalid = title.isNotEmpty() && Challenge.extraTitle(title) == null
    return (if (invalid) "Use a name of 1 to 40 characters on one line." else "One line, 1 to 40 characters.") to invalid
}

@Composable
private fun TitleHelp(title: String) {
    val (text, invalid) = titleHelp(title)
    Text(text, style = Type.caption, color = if (invalid) P.danger else P.textTertiary)
}

/** One scrolling management sheet used by Today and Account: add, rename and archive. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ManageExtrasSheet(tracker: Tracker, onDismiss: () -> Unit) {
    tracker.observe()
    var newTitle by rememberSaveable { mutableStateOf("") }
    var renaming by remember { mutableStateOf<UUID?>(null) }
    var renameTitle by rememberSaveable { mutableStateOf("") }
    var archiving by remember { mutableStateOf<Extra?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val active = tracker.activeExtras

    fun add() {
        error = tracker.addExtra(newTitle)
        if (error == null) newTitle = ""
    }

    AppSheet(onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Manage extras", style = Type.appName, color = P.textPrimary, modifier = Modifier.weight(1f).semantics { heading() })
                TextButton(onDismiss, modifier = Modifier.testTag("extras-done")) { Text("Done", style = Type.pill, color = P.accentText) }
            }
            GlassCard {
                Column(Modifier.padding(Size.sectionHorizontal), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("${active.size}/${Challenge.MAXIMUM_ACTIVE_EXTRAS} extras", style = Type.rowLabel, color = P.textPrimary,
                        modifier = Modifier.testTag("extras-active-count"))
                    Text("To-dos of your own that carry over until done. They never count toward the five or your streak.",
                        style = Type.caption, color = P.textSecondary)
                    if (tracker.canAddExtra) {
                        DesignField(newTitle, { newTitle = it }, "New extra", Icons.AutoMirrored.Outlined.Label, imeAction = ImeAction.Done,
                            onSubmit = { if (Challenge.extraTitle(newTitle) != null) add() }, testTag = "extras-new-title")
                        TitleHelp(newTitle)
                        TintedPill("Add extra", ::add, enabled = Challenge.extraTitle(newTitle) != null, height = 44.dp, expands = true,
                            modifier = Modifier.testTag("extras-add"))
                    } else {
                        Row(Modifier.testTag("extras-cap"), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Outlined.Info, null, tint = P.amberText, modifier = Modifier.size(16.dp))
                            Text("Up to 10 extras. Archive one to add another.", style = Type.caption, color = P.amberText)
                        }
                    }
                    error?.let { FieldError(it) }
                }
            }
            if (active.isNotEmpty()) {
                GlassCard {
                    active.forEachIndexed { index, extra ->
                        if (index > 0) Hairline()
                        Column(Modifier.fillMaxWidth().padding(Size.sectionHorizontal), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (renaming == extra.id) {
                                DesignField(renameTitle, { renameTitle = it }, "Name", Icons.Filled.Edit, imeAction = ImeAction.Done,
                                    testTag = "extras-rename-title")
                                TitleHelp(renameTitle)
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    TintedPill("Save name", {
                                        error = tracker.renameExtra(extra.id, renameTitle)
                                        if (error == null) renaming = null
                                    }, Modifier.weight(1f), enabled = Challenge.extraTitle(renameTitle) != null, height = 44.dp, expands = true)
                                    TintedPill("Cancel", { renaming = null }, Modifier.weight(1f), height = 44.dp, expands = true)
                                }
                            } else {
                                Text(extra.title, style = Type.field, color = P.textPrimary)
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    TintedPill("Rename", { error = null; renameTitle = extra.title; renaming = extra.id },
                                        Modifier.weight(1f).semantics { contentDescription = "Rename ${extra.title}" },
                                        icon = Icons.Filled.Edit, height = 44.dp, expands = true)
                                    TintedPill("Archive", { error = null; renaming = null; archiving = extra },
                                        Modifier.weight(1f).semantics { contentDescription = "Archive ${extra.title}" },
                                        icon = Icons.Outlined.Archive, height = 44.dp, fill = P.dangerTint, foreground = P.danger, expands = true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    archiving?.let { extra ->
        AlertDialog(
            onDismissRequest = { archiving = null },
            title = { Text("Archive extra?") },
            text = { Text("It disappears from today on and can't be restored. Earlier days keep their ticks.") },
            confirmButton = {
                TextButton({ error = tracker.archiveExtra(extra.id); archiving = null }) { Text("Archive ${extra.title}", color = P.danger) }
            },
            dismissButton = { TextButton({ archiving = null }) { Text("Cancel") } },
            containerColor = P.solidGlass, titleContentColor = P.textPrimary, textContentColor = P.textSecondary,
        )
    }
}

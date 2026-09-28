package net.mountanos.setbuddy.android.history

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import net.mountanos.setbuddy.android.ui.NoteEditorDialog
import net.mountanos.setbuddy.shared.data.HistoryRepository
import net.mountanos.setbuddy.shared.data.HistorySessionDetail
import net.mountanos.setbuddy.shared.data.WorkoutSessionRepository
import java.text.NumberFormat
import java.util.Locale
import kotlin.uuid.Uuid

@Composable
fun HistoryScreen(historyRepository: HistoryRepository, sessionRepository: WorkoutSessionRepository) {
    var refreshKey by remember { mutableStateOf(0) }
    val rows = remember(refreshKey) { historyRepository.completedRows() }
    var expanded by remember { mutableStateOf<Uuid?>(null) }
    var editingSessionNoteFor by remember { mutableStateOf<HistorySessionDetail?>(null) }

    if (rows.isEmpty()) {
        Text(
            "No completed workouts yet.",
            modifier = Modifier.fillMaxSize().padding(24.dp),
            textAlign = TextAlign.Center,
        )
        return
    }

    LazyColumn(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        items(rows) { row ->
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { expanded = if (expanded == row.sessionId) null else row.sessionId }
                    .padding(vertical = 8.dp),
            ) {
                Text(row.title, style = MaterialTheme.typography.titleMedium)
                Text(formatDate(row.completedAtEpochMillis), style = MaterialTheme.typography.bodySmall)
                Text("Volume: ${formatVolume(row.totalVolume)}", style = MaterialTheme.typography.bodyMedium)

                if (expanded == row.sessionId) {
                    val detail = remember(refreshKey, row.sessionId) { historyRepository.sessionDetail(row.sessionId) }
                    if (detail != null) {
                        Text(
                            "Scheduled day: ${detail.scheduleDate.year}-${detail.scheduleDate.month}-${detail.scheduleDate.day}",
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(top = 6.dp),
                        )
                        Text(
                            "Total volume: ${formatVolume(detail.totalVolume)}",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        detail.exerciseGroups.forEach { group ->
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text(group.exerciseName, style = MaterialTheme.typography.bodyMedium)
                                Text(formatVolume(group.volume), style = MaterialTheme.typography.bodySmall)
                            }
                            group.sets.forEach { line ->
                                Text("  Set ${line.setIndex + 1}: ${line.weight} × ${line.reps}")
                            }
                        }
                        Text(
                            if (detail.sessionNote.isNullOrBlank()) "Tap to add a workout note" else "Note: ${detail.sessionNote}",
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier
                                .padding(top = 6.dp)
                                .clickable { editingSessionNoteFor = detail },
                        )
                    }
                }
            }
            HorizontalDivider()
        }
    }

    editingSessionNoteFor?.let { detail ->
        NoteEditorDialog(
            title = "Workout note",
            initialNote = detail.sessionNote ?: "",
            onSave = { newNote ->
                sessionRepository.setSessionNote(detail.sessionId, newNote)
                editingSessionNoteFor = null
                refreshKey++
            },
            onDismiss = { editingSessionNoteFor = null },
        )
    }
}

private fun formatVolume(v: Double): String = NumberFormat.getIntegerInstance(Locale.US).format(v.toInt())

private fun formatDate(epochMillis: Long): String {
    if (epochMillis == 0L) return ""
    val local = Instant.fromEpochMilliseconds(epochMillis).toLocalDateTime(TimeZone.currentSystemDefault())
    return "${local.year}-${local.monthNumber.toString().padStart(2, '0')}-${local.dayOfMonth.toString().padStart(2, '0')}"
}

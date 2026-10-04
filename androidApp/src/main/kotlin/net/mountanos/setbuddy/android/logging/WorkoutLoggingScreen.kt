package net.mountanos.setbuddy.android.logging

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import net.mountanos.setbuddy.android.notifications.DailyNotificationScheduler
import net.mountanos.setbuddy.android.ui.NoteEditorDialog
import net.mountanos.setbuddy.android.ui.formatCardioMinutes
import net.mountanos.setbuddy.domain.CalendarDate
import net.mountanos.setbuddy.domain.ExerciseKind
import net.mountanos.setbuddy.domain.VolumeCalculator
import net.mountanos.setbuddy.shared.data.ProgramRepository
import net.mountanos.setbuddy.shared.data.WorkoutSessionRepository
import java.text.NumberFormat
import java.util.Locale
import kotlin.uuid.Uuid

private data class RowKey(val exerciseId: String, val setIndex: Int)
/** [minutes]/[maxHeartRate] are the cardio counterparts of [weight]/[reps]; a row only ever uses one pair. */
private data class RowState(var weight: String, var reps: String, var minutes: String = "", var maxHeartRate: String = "")

@Composable
fun WorkoutLoggingScreen(
    sessionRepository: WorkoutSessionRepository,
    programRepository: ProgramRepository,
    notificationScheduler: DailyNotificationScheduler,
    workoutId: String,
    year: Int,
    month: Int,
    day: Int,
    onDone: () -> Unit,
) {
    val workoutUuid = remember(workoutId) { Uuid.parse(workoutId) }
    val date = remember(year, month, day) { CalendarDate(year, month, day) }
    val workout = remember { sessionRepository.workout(workoutUuid) }
    val session = remember { sessionRepository.getOrCreateActiveSession(workoutUuid, date) }
    val exercises = remember { sessionRepository.exercisesForWorkout(workoutUuid) }
    val loggedSets = remember { sessionRepository.loggedSets(Uuid.parse(session.id)) }
    val reference = remember { sessionRepository.mostRecentLoggedValuesByExercise() }

    var exerciseNotes by remember { mutableStateOf(exercises.associate { it.id to it.note }) }
    var sessionNote by remember { mutableStateOf(session.sessionNote ?: "") }
    var editingExerciseNote by remember { mutableStateOf<String?>(null) }
    var editingSessionNote by remember { mutableStateOf(false) }
    var showFinishConfirm by remember { mutableStateOf(false) }

    val rowState = remember {
        val map = mutableStateMapOf<RowKey, RowState>()
        for (row in loggedSets) {
            val key = RowKey(row.exerciseId, row.setIndex.toInt())
            val displayWeight = if (row.weight != 0.0) row.weight else null
            val displayReps = if (row.reps != 0L) row.reps else null
            map[key] = RowState(
                displayWeight?.toString() ?: "",
                displayReps?.toString() ?: "",
                if (row.cardioMinutes != 0.0) formatCardioMinutes(row.cardioMinutes) else "",
                if (row.maxHeartRate != 0L) row.maxHeartRate.toString() else "",
            )
        }
        map
    }

    // Cardio sets don't count toward weight × reps volume.
    val sessionVolume = exercises.filter { ExerciseKind.fromRaw(it.kind) != ExerciseKind.Cardio }.sumOf { ex ->
        (0 until ex.setCount.toInt()).sumOf { setIndex ->
            val state = rowState[RowKey(ex.id, setIndex)]
            val w = state?.weight?.toDoubleOrNull()
            val r = state?.reps?.toIntOrNull()
            if (w != null || r != null) {
                VolumeCalculator.setVolume(w ?: 0.0, r ?: 0, ex.repsArePerSide == 1L)
            } else {
                0.0
            }
        }
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Text(workout?.name ?: "Workout", style = MaterialTheme.typography.headlineSmall)
        LazyColumn(modifier = Modifier.weight(1f)) {
            items(exercises) { exercise ->
                val isCardio = ExerciseKind.fromRaw(exercise.kind) == ExerciseKind.Cardio
                TextButton(
                    onClick = { editingExerciseNote = exercise.id },
                    modifier = Modifier.padding(top = 12.dp),
                ) {
                    Text(
                        exercise.name + if (!isCardio && exercise.repsArePerSide == 1L) " · Per side ×2" else "",
                        style = MaterialTheme.typography.titleMedium,
                    )
                }
                exerciseNotes[exercise.id]?.takeIf { it.isNotBlank() }?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(start = 16.dp))
                }
                val exerciseUuid = Uuid.parse(exercise.id)
                for (setIndex in 0 until exercise.setCount.toInt()) {
                    val key = RowKey(exercise.id, setIndex)
                    val state = rowState.getOrPut(key) { RowState("", "") }
                    val refSet = reference[exerciseUuid]?.get(setIndex)
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text("Set ${setIndex + 1}", modifier = Modifier.padding(top = 16.dp))
                        if (isCardio) {
                            OutlinedTextField(
                                value = state.minutes,
                                onValueChange = { value ->
                                    rowState[key] = state.copy(minutes = value)
                                    commitCardio(sessionRepository, session.id, exercise.id, setIndex, rowState[key]!!)
                                },
                                label = {
                                    Text(
                                        refSet?.takeIf { it.cardioMinutes > 0 }
                                            ?.let { "Minutes (ref ${formatCardioMinutes(it.cardioMinutes)})" } ?: "Minutes",
                                    )
                                },
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                modifier = Modifier.weight(1f),
                            )
                            OutlinedTextField(
                                value = state.maxHeartRate,
                                onValueChange = { value ->
                                    rowState[key] = state.copy(maxHeartRate = value)
                                    commitCardio(sessionRepository, session.id, exercise.id, setIndex, rowState[key]!!)
                                },
                                label = {
                                    Text(
                                        refSet?.takeIf { it.maxHeartRate > 0 }
                                            ?.let { "Max HR (ref ${it.maxHeartRate})" } ?: "Max HR (bpm)",
                                    )
                                },
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                modifier = Modifier.weight(1f),
                            )
                        } else {
                            OutlinedTextField(
                                value = state.weight,
                                onValueChange = { value ->
                                    rowState[key] = state.copy(weight = value)
                                    commit(sessionRepository, session.id, exercise.id, setIndex, rowState[key]!!)
                                },
                                label = { Text(refSet?.let { "Weight (ref ${it.weight})" } ?: "Weight") },
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                modifier = Modifier.weight(1f),
                            )
                            OutlinedTextField(
                                value = state.reps,
                                onValueChange = { value ->
                                    rowState[key] = state.copy(reps = value)
                                    commit(sessionRepository, session.id, exercise.id, setIndex, rowState[key]!!)
                                },
                                label = { Text(refSet?.let { "Reps (ref ${it.reps})" } ?: "Reps") },
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                }
                HorizontalDivider(modifier = Modifier.padding(top = 8.dp))
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("Session volume", style = MaterialTheme.typography.bodyMedium)
            Text(formatSessionVolume(sessionVolume), style = MaterialTheme.typography.headlineSmall)
        }
        OutlinedButton(
            onClick = { editingSessionNote = true },
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
        ) {
            Text(if (sessionNote.isNotBlank()) "Edit workout note" else "Add a note")
        }
        Button(
            onClick = { showFinishConfirm = true },
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        ) {
            Text("Finish workout")
        }
    }

    editingExerciseNote?.let { exerciseId ->
        NoteEditorDialog(
            title = "Exercise note",
            initialNote = exerciseNotes[exerciseId] ?: "",
            onSave = { newNote ->
                programRepository.setExerciseNote(Uuid.parse(exerciseId), newNote.ifBlank { null })
                exerciseNotes = exerciseNotes + (exerciseId to newNote)
                editingExerciseNote = null
            },
            onDismiss = { editingExerciseNote = null },
        )
    }

    if (editingSessionNote) {
        NoteEditorDialog(
            title = "Workout note",
            initialNote = sessionNote,
            onSave = { newNote ->
                sessionRepository.setSessionNote(Uuid.parse(session.id), newNote)
                sessionNote = newNote
                editingSessionNote = false
            },
            onDismiss = { editingSessionNote = false },
        )
    }

    if (showFinishConfirm) {
        AlertDialog(
            onDismissRequest = { showFinishConfirm = false },
            title = { Text("Finish workout") },
            text = {
                Text(
                    "Only sets you enter are saved. Values from your last workout are for reference only." +
                        if (sessionNote.isNotBlank()) "\n\nNote: $sessionNote" else "",
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    sessionRepository.completeSession(Uuid.parse(session.id), workout?.name ?: "Workout")
                    notificationScheduler.requestReschedule()
                    showFinishConfirm = false
                    onDone()
                }) { Text("Finish workout") }
            },
            dismissButton = { TextButton(onClick = { showFinishConfirm = false }) { Text("Cancel") } },
        )
    }
}

private fun formatSessionVolume(volume: Double): String {
    val intVolume = volume.toInt()
    return if (intVolume >= 1000) {
        NumberFormat.getIntegerInstance(Locale.US).format(intVolume)
    } else {
        intVolume.toString()
    }
}

/** Cardio counterpart of [commit] — minutes accept a comma or a dot as the decimal separator. */
private fun commitCardio(
    repository: WorkoutSessionRepository,
    sessionId: String,
    exerciseId: String,
    setIndex: Int,
    state: RowState,
) {
    val minutes = state.minutes.replace(',', '.').trim().toDoubleOrNull() ?: 0.0
    val maxHeartRate = state.maxHeartRate.trim().toIntOrNull() ?: 0
    repository.updateCardioLoggedSet(Uuid.parse(sessionId), Uuid.parse(exerciseId), setIndex, minutes, maxHeartRate)
}

private fun commit(
    repository: WorkoutSessionRepository,
    sessionId: String,
    exerciseId: String,
    setIndex: Int,
    state: RowState,
) {
    val weight = state.weight.toDoubleOrNull() ?: 0.0
    val reps = state.reps.toIntOrNull() ?: 0
    repository.updateLoggedSet(Uuid.parse(sessionId), Uuid.parse(exerciseId), setIndex, weight, reps)
}

package net.mountanos.setbuddy.android.program

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Note
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import net.mountanos.setbuddy.android.notifications.DailyNotificationScheduler
import net.mountanos.setbuddy.android.settings.ProgramSchedulePreviewDaysSetting
import net.mountanos.setbuddy.android.ui.NoteEditorDialog
import net.mountanos.setbuddy.domain.ScheduledDayKind
import net.mountanos.setbuddy.shared.data.ProgramOutlineRepository
import net.mountanos.setbuddy.shared.data.ProgramRepository
import net.mountanos.setbuddy.shared.data.SchedulePickerValue
import kotlin.uuid.Uuid

@Composable
fun ProgramScreen(
    programRepository: ProgramRepository,
    outlineRepository: ProgramOutlineRepository,
    notificationScheduler: DailyNotificationScheduler,
) {
    val context = LocalContext.current
    var refreshKey by remember { mutableIntStateOf(0) }
    fun refresh() {
        refreshKey++
        notificationScheduler.requestReschedule()
    }

    val scheduleDays = ProgramSchedulePreviewDaysSetting.load(context)
    val outline = remember(refreshKey) {
        programRepository.ensureForwardScheduleFilled()
        outlineRepository.activeProgramOutline()
    }
    val upcoming = remember(refreshKey, scheduleDays) {
        outlineRepository.upcomingScheduleRows(limit = scheduleDays.toLong())
    }

    var editingWorkoutId by remember { mutableStateOf<Uuid?>(null) }
    var editingExerciseNote by remember { mutableStateOf<Pair<Uuid, String>?>(null) }
    var deletingWorkout by remember { mutableStateOf<Pair<Uuid, String>?>(null) }
    var showStartOverConfirm by remember { mutableStateOf(false) }

    if (outline == null) {
        Column(modifier = Modifier.fillMaxSize().padding(24.dp)) {
            Text("No program yet.")
            Button(onClick = { programRepository.createFirstProgram("My program"); refresh() }) {
                Text("Create program")
            }
        }
        return
    }

    var programNameDraft by remember(outline.programId) { mutableStateOf(outline.programName) }

    LazyColumn(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        item {
            OutlinedTextField(
                value = programNameDraft,
                onValueChange = { programNameDraft = it },
                label = { Text("Program name") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { programRepository.renameProgram(programNameDraft); refresh() }),
                modifier = Modifier.fillMaxWidth(),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 8.dp)) {
                OutlinedButton(onClick = { showStartOverConfirm = true }) { Text("Start over") }
                OutlinedButton(onClick = { programRepository.addWorkout(); refresh() }) { Text("Add workout") }
            }

            Text("Upcoming schedule", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp))
        }
        items(upcoming) { row ->
            var menuExpanded by remember { mutableStateOf(false) }
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("${row.date.year}-${row.date.month}-${row.date.day}")
                Row {
                    TextButton(onClick = { menuExpanded = true }) {
                        Text(if (row.isRestDay) "Rest" else (row.workoutTitle ?: "Workout"))
                    }
                    DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                        DropdownMenuItem(
                            text = { Text("Rest") },
                            onClick = {
                                menuExpanded = false
                                programRepository.setScheduleDayShiftingFollowing(row.date, SchedulePickerValue.Rest)
                                refresh()
                            },
                        )
                        outline.workouts.forEach { workout ->
                            DropdownMenuItem(
                                text = { Text(workout.name) },
                                onClick = {
                                    menuExpanded = false
                                    programRepository.setScheduleDayShiftingFollowing(
                                        row.date, SchedulePickerValue.AssignedWorkout(workout.id),
                                    )
                                    refresh()
                                },
                            )
                        }
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text("Add a rest day") },
                            onClick = {
                                menuExpanded = false
                                programRepository.insertRestDayShiftingFollowing(row.date)
                                refresh()
                            },
                        )
                    }
                }
            }
        }

        item {
            HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))
            Text("Workouts", style = MaterialTheme.typography.titleMedium)
        }

        items(outline.workouts) { workout ->
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                TextButton(onClick = { editingWorkoutId = workout.id }) {
                    Text(workout.name, style = MaterialTheme.typography.titleSmall)
                }
                TextButton(onClick = { deletingWorkout = workout.id to workout.name }) {
                    Text("Delete")
                }
            }
            workout.exercises.forEach { exercise ->
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    TextButton(onClick = { editingExerciseNote = exercise.id to (exercise.note ?: "") }) {
                        Text("${exercise.name} × ${exercise.setCount}" + if (exercise.repsArePerSide) " · Per side ×2" else "")
                    }
                    if (!exercise.note.isNullOrBlank()) {
                        Icon(Icons.Filled.Note, contentDescription = "Has note", modifier = Modifier.padding(top = 12.dp))
                    }
                }
            }
            HorizontalDivider(modifier = Modifier.padding(top = 8.dp))
        }
    }

    editingWorkoutId?.let { workoutId ->
        WorkoutEditorDialog(
            workoutId = workoutId,
            programRepository = programRepository,
            outlineRepository = outlineRepository,
            onDismiss = { editingWorkoutId = null; refresh() },
        )
    }

    editingExerciseNote?.let { (exerciseId, note) ->
        NoteEditorDialog(
            title = "Exercise note",
            initialNote = note,
            onSave = { newNote ->
                programRepository.setExerciseNote(exerciseId, newNote.ifBlank { null })
                editingExerciseNote = null
                refresh()
            },
            onDismiss = { editingExerciseNote = null },
        )
    }

    deletingWorkout?.let { (workoutId, name) ->
        AlertDialog(
            onDismissRequest = { deletingWorkout = null },
            title = { Text("Delete workout?") },
            text = { Text("Scheduled days that used this workout become rest days.") },
            confirmButton = {
                TextButton(onClick = {
                    programRepository.deleteWorkout(workoutId)
                    deletingWorkout = null
                    refresh()
                }) { Text("Delete \"$name\"") }
            },
            dismissButton = { TextButton(onClick = { deletingWorkout = null }) { Text("Cancel") } },
        )
    }

    if (showStartOverConfirm) {
        AlertDialog(
            onDismissRequest = { showStartOverConfirm = false },
            title = { Text("Start over?") },
            text = {
                Text(
                    "Your current program and schedule are removed and replaced with a fresh starter. Completed " +
                        "workouts stay in History; any workout in progress is cleared. The new program uses the " +
                        "name in the title field above (or \"My program\" if it's empty).",
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val name = programNameDraft.ifBlank { "My program" }
                    programRepository.startOverFreshProgram(name)
                    showStartOverConfirm = false
                    refresh()
                }) { Text("Start over") }
            },
            dismissButton = { TextButton(onClick = { showStartOverConfirm = false }) { Text("Cancel") } },
        )
    }
}

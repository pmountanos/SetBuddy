package net.mountanos.setbuddy.android.program

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import net.mountanos.setbuddy.shared.data.ProgramExerciseOutline
import net.mountanos.setbuddy.shared.data.ProgramOutlineRepository
import net.mountanos.setbuddy.shared.data.ProgramRepository
import kotlin.uuid.Uuid

/** Ported from `WorkoutTemplateEditorSheet.swift` — workout name + per-exercise name/set-count/per-side editing, reorder, delete, add. */
@Composable
fun WorkoutEditorDialog(
    workoutId: Uuid,
    programRepository: ProgramRepository,
    outlineRepository: ProgramOutlineRepository,
    onDismiss: () -> Unit,
) {
    var reloadKey by remember { mutableIntStateOf(0) }
    val outline = remember(reloadKey) { outlineRepository.activeProgramOutline() }
    val workout = outline?.workouts?.firstOrNull { it.id == workoutId }
    fun reload() { reloadKey++ }

    var nameDraft by remember(reloadKey) { mutableStateOf(workout?.name ?: "") }

    fun commitAndDismiss() {
        if (nameDraft.isNotBlank() && nameDraft != workout?.name) {
            programRepository.renameWorkout(workoutId, nameDraft)
        }
        onDismiss()
    }

    Dialog(onDismissRequest = { commitAndDismiss() }) {
        Surface(shape = MaterialTheme.shapes.large) {
            Column(modifier = Modifier.padding(24.dp).fillMaxWidth()) {
                Text("Edit workout", style = MaterialTheme.typography.titleLarge)
                OutlinedTextField(
                    value = nameDraft,
                    onValueChange = { nameDraft = it },
                    label = { Text("Workout name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                )
                Text(
                    "Per side: each rep is one limb (e.g. dumbbell). Volume doubles to count both sides.",
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(top = 8.dp),
                )

                val exercises = workout?.exercises.orEmpty()
                LazyColumn(modifier = Modifier.padding(top = 12.dp)) {
                    itemsIndexed(exercises, key = { _, ex -> ex.id.toString() }) { index, exercise ->
                        ExerciseEditorRow(
                            exercise = exercise,
                            canMoveUp = index > 0,
                            canMoveDown = index < exercises.size - 1,
                            onNameChange = { newName -> programRepository.setExerciseName(exercise.id, newName) },
                            onSetCountChange = { count -> programRepository.setExerciseSetCount(exercise.id, count); reload() },
                            onPerSideChange = { value -> programRepository.setExerciseRepsPerSide(exercise.id, value); reload() },
                            onMoveUp = {
                                val ids = exercises.map { it.id }.toMutableList()
                                ids.removeAt(index); ids.add(index - 1, exercise.id)
                                programRepository.reorderExercises(workoutId, ids)
                                reload()
                            },
                            onMoveDown = {
                                val ids = exercises.map { it.id }.toMutableList()
                                ids.removeAt(index); ids.add(index + 1, exercise.id)
                                programRepository.reorderExercises(workoutId, ids)
                                reload()
                            },
                            onDelete = { programRepository.deleteExercise(exercise.id); reload() },
                        )
                        HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                    }
                }

                OutlinedButton(
                    onClick = { programRepository.addExercise(workoutId); reload() },
                    modifier = Modifier.padding(top = 8.dp),
                ) { Text("Add exercise") }

                Row(modifier = Modifier.fillMaxWidth().padding(top = 16.dp), horizontalArrangement = Arrangement.End) {
                    Button(onClick = { commitAndDismiss() }) { Text("Done") }
                }
            }
        }
    }
}

@Composable
private fun ExerciseEditorRow(
    exercise: ProgramExerciseOutline,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onNameChange: (String) -> Unit,
    onSetCountChange: (Int) -> Unit,
    onPerSideChange: (Boolean) -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onDelete: () -> Unit,
) {
    var name by remember(exercise.id) { mutableStateOf(exercise.name) }
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it; onNameChange(it) },
                label = { Text("Exercise name") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = onMoveUp, enabled = canMoveUp) {
                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "Move up")
            }
            IconButton(onClick = onMoveDown, enabled = canMoveDown) {
                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "Move down")
            }
            IconButton(onClick = onDelete) {
                Icon(Icons.Filled.Delete, contentDescription = "Delete exercise")
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("Sets to log: ${exercise.setCount}")
            TextButton(onClick = { if (exercise.setCount > 1) onSetCountChange(exercise.setCount - 1) }) { Text("−") }
            TextButton(onClick = { if (exercise.setCount < 20) onSetCountChange(exercise.setCount + 1) }) { Text("+") }
            Spacer(modifier = Modifier.weight(1f))
            Text("Per side")
            Switch(checked = exercise.repsArePerSide, onCheckedChange = onPerSideChange)
        }
    }
}

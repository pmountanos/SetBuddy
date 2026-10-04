package net.mountanos.setbuddy.android.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import net.mountanos.setbuddy.android.notifications.DailyNotificationScheduler
import net.mountanos.setbuddy.domain.CalendarDate
import net.mountanos.setbuddy.domain.TodayScheduleResolver
import net.mountanos.setbuddy.domain.TodayScheduleStatus
import net.mountanos.setbuddy.shared.data.ProgramOutlineRepository
import net.mountanos.setbuddy.shared.data.ProgramRepository
import net.mountanos.setbuddy.shared.data.SchedulePickerValue
import net.mountanos.setbuddy.shared.data.WorkoutSessionRepository

@Composable
fun TodayScreen(
    programRepository: ProgramRepository,
    outlineRepository: ProgramOutlineRepository,
    sessionRepository: WorkoutSessionRepository,
    notificationScheduler: DailyNotificationScheduler,
    onOpenWorkout: (workoutId: String, day: CalendarDate) -> Unit,
) {
    var refreshKey by remember { mutableIntStateOf(0) }
    val today = remember(refreshKey) { CalendarDate.today() }

    val hasProgram = remember(refreshKey) { programRepository.activeProgram() != null }
    val availableWorkouts = remember(refreshKey) {
        outlineRepository.activeProgramOutline()?.workouts.orEmpty()
    }

    val status = remember(refreshKey) {
        val program = programRepository.activeProgram()
        if (program == null) {
            TodayScheduleStatus.NoProgram
        } else {
            val schedule = programRepository.calendarSchedule(program)
            val titles = programRepository.workoutTitles(program)
            val base = TodayScheduleResolver.status(today, schedule, titles)
            when (base) {
                is TodayScheduleStatus.WorkoutDay -> {
                    if (sessionRepository.hasCompletedSession(base.workoutId, today)) {
                        TodayScheduleStatus.WorkoutAlreadyFinished(base.workoutId, base.title)
                    } else if (sessionRepository.activeSession(base.workoutId, today) != null) {
                        TodayScheduleStatus.WorkoutInProgress(base.workoutId, base.title)
                    } else {
                        base
                    }
                }
                else -> base
            }
        }
    }

    var changePlanMenuExpanded by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        when (status) {
            is TodayScheduleStatus.NoProgram -> Text("Set up your training program on the Program tab.")
            is TodayScheduleStatus.DayNotScheduled -> Text("No plan for today yet.")
            is TodayScheduleStatus.RestDay -> Text("Rest day")
            is TodayScheduleStatus.WorkoutAlreadyFinished -> {
                Text(status.title)
                Text("Finished for today ✓")
                OutlinedButton(onClick = {
                    sessionRepository.reopenCompletedSession(status.workoutId, today)
                    notificationScheduler.requestReschedule()
                    refreshKey++
                    onOpenWorkout(status.workoutId.toString(), today)
                }) {
                    Text("Reopen")
                }
            }
            is TodayScheduleStatus.WorkoutDay -> {
                Text(status.title)
                Button(onClick = { onOpenWorkout(status.workoutId.toString(), today) }) {
                    Text("Start")
                }
            }
            is TodayScheduleStatus.WorkoutInProgress -> {
                Text(status.title)
                Button(onClick = { onOpenWorkout(status.workoutId.toString(), today) }) {
                    Text("Continue")
                }
            }
        }

        if (hasProgram) {
            TextButton(onClick = { changePlanMenuExpanded = true }) {
                Text("Change today's plan", style = MaterialTheme.typography.bodyMedium)
            }
            DropdownMenu(expanded = changePlanMenuExpanded, onDismissRequest = { changePlanMenuExpanded = false }) {
                DropdownMenuItem(
                    text = { Text("Rest") },
                    onClick = {
                        changePlanMenuExpanded = false
                        programRepository.setScheduleDayShiftingFollowing(today, SchedulePickerValue.Rest)
                        notificationScheduler.requestReschedule()
                        refreshKey++
                    },
                )
                availableWorkouts.forEach { workout ->
                    DropdownMenuItem(
                        text = { Text(workout.name) },
                        onClick = {
                            changePlanMenuExpanded = false
                            programRepository.setScheduleDayShiftingFollowing(
                                today, SchedulePickerValue.AssignedWorkout(workout.id),
                            )
                            notificationScheduler.requestReschedule()
                            refreshKey++
                        },
                    )
                }
            }
        }
    }
}

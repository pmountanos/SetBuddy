package net.mountanos.setbuddy.domain

import kotlin.uuid.Uuid

sealed class TodayScheduleStatus {
    data object NoProgram : TodayScheduleStatus()
    data object DayNotScheduled : TodayScheduleStatus()
    data object RestDay : TodayScheduleStatus()
    data class WorkoutDay(val workoutId: Uuid, val title: String) : TodayScheduleStatus()

    /** Same scheduled workout as [WorkoutDay], but an incomplete session exists for today (user can continue logging). */
    data class WorkoutInProgress(val workoutId: Uuid, val title: String) : TodayScheduleStatus()

    /** Scheduled workout for today is already finished; offer Reopen instead of Start. */
    data class WorkoutAlreadyFinished(val workoutId: Uuid, val title: String) : TodayScheduleStatus()
}

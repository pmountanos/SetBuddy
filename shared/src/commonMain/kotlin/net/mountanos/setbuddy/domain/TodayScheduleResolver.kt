package net.mountanos.setbuddy.domain

import kotlin.uuid.Uuid

object TodayScheduleResolver {
    /** Resolves "right now" using calendar-date schedule entries and workout titles. */
    fun status(
        today: CalendarDate,
        schedule: ProgramCalendarSchedule,
        workoutNames: Map<Uuid, String>,
    ): TodayScheduleStatus {
        val kind = schedule.scheduledKind(today) ?: return TodayScheduleStatus.DayNotScheduled
        return when (kind) {
            is ScheduledDayKind.Rest -> TodayScheduleStatus.RestDay
            is ScheduledDayKind.Workout -> {
                val title = workoutNames[kind.workoutId] ?: "Workout"
                TodayScheduleStatus.WorkoutDay(workoutId = kind.workoutId, title = title)
            }
        }
    }
}

package net.mountanos.setbuddy.shared.data

import net.mountanos.setbuddy.domain.CalendarDate
import net.mountanos.setbuddy.domain.ExerciseKind
import net.mountanos.setbuddy.domain.WorkoutTemplateDisplaySort
import net.mountanos.setbuddy.shared.db.SetBuddyDatabase
import net.mountanos.setbuddy.shared.db.Workout
import kotlin.uuid.Uuid

data class ProgramExerciseOutline(
    val id: Uuid,
    val name: String,
    val sortOrder: Int,
    val setCount: Int,
    val note: String?,
    val repsArePerSide: Boolean,
    /** Strength (weight/reps) or cardio (minutes/max heart rate). */
    val kind: ExerciseKind,
)

data class ProgramWorkoutOutline(val id: Uuid, val name: String, val exercises: List<ProgramExerciseOutline>)

data class ProgramOutline(val programId: Uuid, val programName: String, val workouts: List<ProgramWorkoutOutline>)

data class ProgramScheduleDayRow(val date: CalendarDate, val isRestDay: Boolean, val workoutId: Uuid?, val workoutTitle: String?)

/** Ported from `Data/Repositories/ProgramOutlineRepository.swift`. */
class ProgramOutlineRepository(private val db: SetBuddyDatabase) {
    private val q = db.setBuddyQueries

    fun activeProgramOutline(): ProgramOutline? {
        val program = q.selectActiveProgram().executeAsOneOrNull() ?: return null
        val workouts = q.selectWorkoutsForProgram(program.id).executeAsList()
            // sortOrder (import/cycle position) first; falls back to the naming heuristic on ties (e.g. every
            // workout still at the default 0 on an install that predates the column, until it's re-imported).
            .sortedWith(compareBy<Workout> { it.sortOrder }.thenBy(WorkoutTemplateDisplaySort.comparator) { it.name })
            .map { workout ->
                val exercises = q.selectExercisesForWorkout(workout.id).executeAsList().map { ex ->
                    ProgramExerciseOutline(
                        id = Uuid.parse(ex.id),
                        name = ex.name,
                        sortOrder = ex.sortOrder.toInt(),
                        setCount = ex.setCount.toInt(),
                        note = ex.note,
                        repsArePerSide = ex.repsArePerSide == 1L,
                        kind = ExerciseKind.fromRaw(ex.kind),
                    )
                }
                ProgramWorkoutOutline(Uuid.parse(workout.id), workout.name, exercises)
            }
        return ProgramOutline(Uuid.parse(program.id), program.name, workouts)
    }

    fun upcomingScheduleRows(limit: Long): List<ProgramScheduleDayRow> {
        val program = q.selectActiveProgram().executeAsOneOrNull() ?: return emptyList()
        val today = CalendarDate.today()
        val titles = q.selectWorkoutsForProgram(program.id).executeAsList().associate { it.id to it.name }
        return q.selectUpcomingSchedule(program.id, today.year.toLong(), today.month.toLong(), today.day.toLong(), limit)
            .executeAsList()
            .map { entry ->
                val workoutId = entry.workoutId
                ProgramScheduleDayRow(
                    date = CalendarDate(entry.year.toInt(), entry.month.toInt(), entry.day.toInt()),
                    isRestDay = entry.isRestDay == 1L,
                    workoutId = workoutId?.let { Uuid.parse(it) },
                    workoutTitle = workoutId?.let { titles[it] },
                )
            }
    }
}

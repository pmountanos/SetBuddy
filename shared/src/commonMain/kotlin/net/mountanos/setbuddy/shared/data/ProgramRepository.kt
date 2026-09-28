package net.mountanos.setbuddy.shared.data

import kotlinx.datetime.Clock
import net.mountanos.setbuddy.domain.CalendarDate
import net.mountanos.setbuddy.domain.ExerciseCarryoverMatcher
import net.mountanos.setbuddy.domain.ProgramCalendarSchedule
import net.mountanos.setbuddy.domain.ScheduledDayKind
import net.mountanos.setbuddy.shared.db.Program
import net.mountanos.setbuddy.shared.db.SetBuddyDatabase
import net.mountanos.setbuddy.shared.db.Workout
import kotlin.uuid.Uuid

class ProgramAlreadyExistsException : Exception("A program already exists")

/** What to assign to one calendar day when editing the schedule from the Program tab. */
sealed class SchedulePickerValue {
    data object Rest : SchedulePickerValue()
    data class AssignedWorkout(val workoutId: Uuid) : SchedulePickerValue()
}

/** Ported from `Data/Repositories/ProgramRepository.swift`. */
class ProgramRepository(private val db: SetBuddyDatabase, private val defaultSetCount: Int = 4) {
    private val q = db.setBuddyQueries
    private val forwardScheduleHorizonDays = 196

    fun activeProgram(): Program? = q.selectActiveProgram().executeAsOneOrNull()

    /** Active program's exercises, for `ExerciseCarryoverMatcher` staging before a re-import replaces the program. */
    fun existingExercisesForCarryover(): List<ExerciseCarryoverMatcher.ExistingExercise> {
        val program = activeProgram() ?: return emptyList()
        return q.selectExercisesForProgram(program.id).executeAsList()
            .map { ExerciseCarryoverMatcher.ExistingExercise(Uuid.parse(it.id), it.name) }
    }

    fun calendarSchedule(program: Program): ProgramCalendarSchedule {
        val schedule = ProgramCalendarSchedule()
        q.selectScheduleForProgram(program.id).executeAsList().forEach { entry ->
            val date = CalendarDate(entry.year.toInt(), entry.month.toInt(), entry.day.toInt())
            val kind = if (entry.isRestDay == 1L) {
                ScheduledDayKind.Rest
            } else {
                ScheduledDayKind.Workout(Uuid.parse(entry.workoutId ?: return@forEach))
            }
            schedule.set(kind, date)
        }
        return schedule
    }

    fun workoutTitles(program: Program): Map<Uuid, String> =
        q.selectWorkoutsForProgram(program.id).executeAsList().associate { Uuid.parse(it.id) to it.name }

    fun ensureForwardScheduleFilled(daysAhead: Int = forwardScheduleHorizonDays) {
        val program = activeProgram() ?: return
        val today = CalendarDate.today()
        val existing = q.selectScheduleForProgram(program.id).executeAsList()
            .map { CalendarDate(it.year.toInt(), it.month.toInt(), it.day.toInt()) }
            .toMutableSet()
        db.transaction {
            for (offset in 0 until daysAhead) {
                val date = today.addingDays(offset)
                if (date in existing) continue
                q.upsertScheduleEntry(
                    id = Uuid.random().toString(),
                    programId = program.id,
                    year = date.year.toLong(),
                    month = date.month.toLong(),
                    day = date.day.toLong(),
                    isRestDay = 1L,
                    workoutId = null,
                )
                existing.add(date)
            }
        }
    }

    /** Creates the only program when the store is empty: one starter workout with one exercise, plus a forward schedule (all rest until you assign workouts in Program). */
    fun createFirstProgram(name: String): Program {
        if (activeProgram() != null) throw ProgramAlreadyExistsException()
        val trimmed = name.trim()
        val programName = trimmed.ifEmpty { "My program" }
        val programId = Uuid.random().toString()
        val workoutId = Uuid.random().toString()
        val exerciseId = Uuid.random().toString()

        db.transaction {
            val nextOrder = q.nextProgramRowOrder().executeAsOne()
            q.insertProgram(programId, programName, nextOrder)
            q.insertWorkout(workoutId, programId, "Workout 1")
            q.insertExercise(exerciseId, workoutId, "Exercise 1", 0, defaultSetCount.toLong(), null, 0)
        }
        ensureForwardScheduleFilled()
        return q.selectActiveProgram().executeAsOne()
    }

    /** Removes all programs (schedule/workouts/exercises cascade) and inserts a fresh starter program. Completed sessions in History are untouched — they aren't foreign-keyed to Workout. */
    fun startOverFreshProgram(name: String): Program {
        db.transaction {
            q.deleteAllPrograms()
        }
        return createFirstProgram(name)
    }

    fun renameProgram(name: String) {
        val program = activeProgram() ?: return
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        q.renameProgram(trimmed, program.id)
    }

    fun renameWorkout(id: Uuid, name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        q.renameWorkout(trimmed, id.toString())
    }

    fun setScheduleDay(date: CalendarDate, value: SchedulePickerValue) {
        val program = activeProgram() ?: return
        applyScheduleDay(program.id, date, value)
    }

    /** Assigns [value] to [start] and shifts every day after it forward by one, matching the iOS "insert" semantics used when today's plan changes retroactively. */
    fun setScheduleDayShiftingFollowing(from: CalendarDate, value: SchedulePickerValue, cascadeDays: Int = forwardScheduleHorizonDays) {
        val program = activeProgram() ?: return
        val existing = q.selectScheduleForProgram(program.id).executeAsList()
            .associateBy { CalendarDate(it.year.toInt(), it.month.toInt(), it.day.toInt()) }

        db.transaction {
            applyScheduleDay(program.id, from, value)
            // Shift every subsequent day's assignment forward by one (day N's old value moves to day N+1).
            var previous: SchedulePickerValue = value
            for (offset in 1..cascadeDays) {
                val date = from.addingDays(offset)
                val entry = existing[date]
                val current = when {
                    entry == null -> SchedulePickerValue.Rest
                    entry.isRestDay == 1L -> SchedulePickerValue.Rest
                    else -> SchedulePickerValue.AssignedWorkout(Uuid.parse(entry.workoutId!!))
                }
                applyScheduleDay(program.id, date, previous)
                previous = current
            }
        }
    }

    fun insertRestDayShiftingFollowing(start: CalendarDate, cascadeDays: Int = forwardScheduleHorizonDays) {
        setScheduleDayShiftingFollowing(start, SchedulePickerValue.Rest, cascadeDays)
    }

    private fun applyScheduleDay(programId: String, date: CalendarDate, value: SchedulePickerValue) {
        q.upsertScheduleEntry(
            id = Uuid.random().toString(),
            programId = programId,
            year = date.year.toLong(),
            month = date.month.toLong(),
            day = date.day.toLong(),
            isRestDay = if (value is SchedulePickerValue.Rest) 1L else 0L,
            workoutId = (value as? SchedulePickerValue.AssignedWorkout)?.workoutId?.toString(),
        )
    }

    fun addWorkout(name: String = "New workout"): Workout {
        val program = activeProgram() ?: throw IllegalStateException("No active program")
        val id = Uuid.random().toString()
        q.insertWorkout(id, program.id, name)
        return q.selectWorkoutById(id).executeAsOne()
    }

    fun deleteWorkout(id: Uuid) {
        q.deleteWorkout(id.toString())
    }

    fun addExercise(workoutId: Uuid, name: String = "New exercise", setCount: Int = 4) {
        val existing = q.selectExercisesForWorkout(workoutId.toString()).executeAsList()
        val id = Uuid.random().toString()
        q.insertExercise(id, workoutId.toString(), name, existing.size.toLong(), setCount.toLong(), null, 0)
    }

    fun deleteExercise(id: Uuid) {
        q.deleteExercise(id.toString())
    }

    fun setExerciseName(id: Uuid, name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        q.updateExerciseName(trimmed, id.toString())
    }

    fun setExerciseSetCount(id: Uuid, setCount: Int) {
        q.updateExerciseSetCount(setCount.toLong(), id.toString())
    }

    fun setExerciseRepsPerSide(id: Uuid, value: Boolean) {
        q.updateExerciseRepsPerSide(if (value) 1L else 0L, id.toString())
    }

    fun setExerciseNote(id: Uuid, note: String?) {
        q.updateExerciseNote(note, id.toString())
    }

    fun reorderExercises(workoutId: Uuid, orderedExerciseIds: List<Uuid>) {
        db.transaction {
            orderedExerciseIds.forEachIndexed { index, exerciseId ->
                q.updateExerciseSortOrder(index.toLong(), exerciseId.toString())
            }
        }
    }
}

internal fun nowEpochMillis(): Long = Clock.System.now().toEpochMilliseconds()

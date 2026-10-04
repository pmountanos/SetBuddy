package net.mountanos.setbuddy.shared.data

import kotlinx.datetime.Clock
import net.mountanos.setbuddy.domain.CalendarDate
import net.mountanos.setbuddy.domain.ExerciseCarryoverMatcher
import net.mountanos.setbuddy.domain.ExerciseKind
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
            q.insertWorkout(workoutId, programId, "Workout 1", 0)
            q.insertExercise(exerciseId, workoutId, "Exercise 1", 0, defaultSetCount.toLong(), null, 0, ExerciseKind.Strength.rawValue)
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

    /**
     * Assigns [value] to [from] and shifts every day after it forward by one, matching the iOS "insert" semantics
     * used when today's plan changes retroactively.
     *
     * @param skipIfUnchanged when `true`, does nothing if [from] already equals [value] (picker no-op). **Add a
     *        rest day** passes `false` so inserting rest still pushes the schedule even when that day was already rest.
     * @param preferNearestRecurrence when `true` and [value] already recurs within the next
     *        [NEAR_DUPLICATE_SEARCH_WINDOW] days, rotates just that bounded window ([from] through the recurrence)
     *        instead of shifting the entire remaining horizon. Pass `false` for an unconditional insert.
     */
    fun setScheduleDayShiftingFollowing(
        from: CalendarDate,
        value: SchedulePickerValue,
        cascadeDays: Int = forwardScheduleHorizonDays,
        skipIfUnchanged: Boolean = true,
        preferNearestRecurrence: Boolean = true,
    ) {
        val program = activeProgram() ?: return
        val existing = q.selectScheduleForProgram(program.id).executeAsList()
            .associateBy { CalendarDate(it.year.toInt(), it.month.toInt(), it.day.toInt()) }

        // Days with no row yet (past the stored horizon) count as rest.
        val oldValues = (0..cascadeDays).map { offset ->
            val entry = existing[from.addingDays(offset)]
            val workoutId = entry?.workoutId
            if (entry == null || entry.isRestDay == 1L || workoutId == null) {
                SchedulePickerValue.Rest
            } else {
                SchedulePickerValue.AssignedWorkout(Uuid.parse(workoutId))
            }
        }
        if (skipIfUnchanged && oldValues[0] == value) return

        // If `value` already recurs soon (e.g. pulling a workout that's due again in a few days to today, rather
        // than genuinely inserting something new), rotate just that bounded window instead of shifting the entire
        // rest of the horizon. Otherwise that recurrence shows up again a few days later as an apparent
        // duplicate/out-of-order repeat, and every day after it runs one calendar day later than the
        // spreadsheet's actual cycle from then on — compounding with every such edit. Bounded to a search window
        // so a coincidental match far in the future still falls through to a plain insert.
        val recurrence = if (preferNearestRecurrence) {
            (1..minOf(NEAR_DUPLICATE_SEARCH_WINDOW, cascadeDays)).firstOrNull { oldValues[it] == value }
        } else {
            null
        }

        db.transaction {
            applyScheduleDay(program.id, from, value)
            // Day N's old value moves to day N+1, through the recurrence if there is one, else the whole horizon.
            for (offset in 1..(recurrence ?: cascadeDays)) {
                applyScheduleDay(program.id, from.addingDays(offset), oldValues[offset - 1])
            }
        }
    }

    /** Always inserts a genuinely new rest day — never swaps to a rest day that's already coming up soon, since "add a rest day" specifically means one more day off, not a rearrangement. */
    fun insertRestDayShiftingFollowing(start: CalendarDate, cascadeDays: Int = forwardScheduleHorizonDays) {
        setScheduleDayShiftingFollowing(
            start, SchedulePickerValue.Rest, cascadeDays, skipIfUnchanged = false, preferNearestRecurrence = false,
        )
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
        db.transaction {
            q.insertWorkout(id, program.id, name, q.nextWorkoutSortOrder(program.id).executeAsOne())
        }
        return q.selectWorkoutById(id).executeAsOne()
    }

    fun deleteWorkout(id: Uuid) {
        q.deleteWorkout(id.toString())
    }

    fun addExercise(workoutId: Uuid, name: String = "New exercise", setCount: Int = 4) {
        val existing = q.selectExercisesForWorkout(workoutId.toString()).executeAsList()
        val id = Uuid.random().toString()
        q.insertExercise(
            id, workoutId.toString(), name, existing.size.toLong(), setCount.toLong(), null, 0,
            ExerciseKind.Strength.rawValue,
        )
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

    /**
     * Switching to cardio resets the set count to **1** — a cardio exercise is normally a single set (one
     * duration/heart-rate reading), not a strength-style multi-set default. Still adjustable afterward.
     */
    fun setExerciseKind(id: Uuid, kind: ExerciseKind) {
        db.transaction {
            q.updateExerciseKind(kind.rawValue, id.toString())
            if (kind == ExerciseKind.Cardio) q.updateExerciseSetCount(1, id.toString())
        }
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

/**
 * How many days ahead `setScheduleDayShiftingFollowing` looks for the value already recurring, to swap to it
 * (bounded rotation) instead of inserting a duplicate and shifting the whole remaining horizon. Generous upper
 * bound on realistic workout-rotation cycle lengths.
 */
const val NEAR_DUPLICATE_SEARCH_WINDOW = 60

internal fun nowEpochMillis(): Long = Clock.System.now().toEpochMilliseconds()

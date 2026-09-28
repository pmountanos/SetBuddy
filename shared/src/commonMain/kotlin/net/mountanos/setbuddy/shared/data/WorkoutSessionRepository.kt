package net.mountanos.setbuddy.shared.data

import net.mountanos.setbuddy.domain.CalendarDate
import net.mountanos.setbuddy.shared.db.Exercise
import net.mountanos.setbuddy.shared.db.LoggedSet
import net.mountanos.setbuddy.shared.db.SetBuddyDatabase
import net.mountanos.setbuddy.shared.db.WorkoutSession
import kotlin.uuid.Uuid

/** Ported from `Data/Repositories/WorkoutSessionRepository.swift`. */
class WorkoutSessionRepository(private val db: SetBuddyDatabase) {
    private val q = db.setBuddyQueries

    fun workout(templateId: Uuid) = q.selectWorkoutById(templateId.toString()).executeAsOneOrNull()

    fun exercisesForWorkout(templateId: Uuid): List<Exercise> =
        q.selectExercisesForWorkout(templateId.toString()).executeAsList()

    fun activeSession(templateId: Uuid, day: CalendarDate): WorkoutSession? {
        val session = q.selectSessionForDay(
            templateId.toString(), day.year.toLong(), day.month.toLong(), day.day.toLong()
        ).executeAsOneOrNull()
        return session?.takeIf { it.isComplete == 0L }
    }

    fun hasCompletedSession(templateId: Uuid, day: CalendarDate): Boolean {
        val session = q.selectSessionForDay(
            templateId.toString(), day.year.toLong(), day.month.toLong(), day.day.toLong()
        ).executeAsOneOrNull()
        return session?.isComplete == 1L
    }

    /** Returns the in-progress session for [templateId]/[day], creating it (and its logged-set rows) if needed. */
    fun getOrCreateActiveSession(templateId: Uuid, day: CalendarDate): WorkoutSession {
        activeSession(templateId, day)?.let {
            syncLoggedSetsToTemplate(it)
            return it
        }
        val sessionId = Uuid.random().toString()
        db.transaction {
            q.insertSession(sessionId, templateId.toString(), day.year.toLong(), day.month.toLong(), day.day.toLong(), nowEpochMillis())
        }
        val session = q.selectSessionById(sessionId).executeAsOne()
        syncLoggedSetsToTemplate(session)
        return session
    }

    /** Adds missing logged-set rows and removes rows beyond the current template's set count / repsArePerSide, mirroring `populateMissingLoggedSets`/`pruneLoggedSetsExceedingTemplate`. */
    private fun syncLoggedSetsToTemplate(session: WorkoutSession) {
        val exercises = q.selectExercisesForWorkout(session.workoutTemplateId).executeAsList()
        db.transaction {
            for (exercise in exercises) {
                for (setIndex in 0 until exercise.setCount) {
                    q.insertLoggedSet(
                        id = Uuid.random().toString(),
                        sessionId = session.id,
                        exerciseId = exercise.id,
                        setIndex = setIndex,
                        repsArePerSide = if (exercise.repsArePerSide == 1L) 1L else 0L,
                    )
                }
                q.deleteLoggedSetsExceedingSetCount(session.id, exercise.id, exercise.setCount)
            }
        }
    }

    fun loggedSets(sessionId: Uuid): List<LoggedSet> =
        q.selectLoggedSetsForSession(sessionId.toString()).executeAsList()

    /** Most recent logged value **per exercise, any workout** — read via `WorkoutLoggingViewModel` for the reference display. Keyed by exerciseId -> setIndex -> row. */
    fun mostRecentLoggedValuesByExercise(): Map<Uuid, Map<Int, LoggedSet>> {
        val result = mutableMapOf<Uuid, MutableMap<Int, LoggedSet>>()
        for (row in q.selectAllCompletedLoggedSetsByRecency().executeAsList()) {
            val exerciseId = Uuid.parse(row.exerciseId)
            val bucket = result.getOrPut(exerciseId) { mutableMapOf() }
            val setIndex = row.setIndex.toInt()
            if (setIndex !in bucket) bucket[setIndex] = row
        }
        return result
    }

    fun updateLoggedSet(sessionId: Uuid, exerciseId: Uuid, setIndex: Int, weight: Double, reps: Int) {
        q.updateLoggedSet(weight, reps.toLong(), sessionId.toString(), exerciseId.toString(), setIndex.toLong())
    }

    fun completeSession(sessionId: Uuid, workoutTitle: String) {
        db.transaction {
            q.deleteNonEnteredLoggedSets(sessionId.toString())
            q.completeSession(nowEpochMillis(), workoutTitle, sessionId.toString())
        }
    }

    fun setSessionNote(sessionId: Uuid, note: String) {
        q.updateSessionNote(note, sessionId.toString())
    }
}

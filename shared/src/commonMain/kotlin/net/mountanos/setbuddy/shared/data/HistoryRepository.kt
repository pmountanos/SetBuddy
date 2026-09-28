package net.mountanos.setbuddy.shared.data

import net.mountanos.setbuddy.domain.CalendarDate
import net.mountanos.setbuddy.domain.VolumeCalculator
import net.mountanos.setbuddy.shared.db.SetBuddyDatabase
import kotlin.uuid.Uuid

data class HistoryCompletedRow(
    val sessionId: Uuid,
    val title: String,
    val completedAtEpochMillis: Long,
    val totalVolume: Double,
    val hasSessionNote: Boolean,
)

data class HistorySessionSetLine(val setIndex: Int, val weight: Double, val reps: Int, val repsArePerSide: Boolean) {
    val volume: Double get() = VolumeCalculator.setVolume(weight, reps, repsArePerSide)
}

data class HistorySessionExerciseGroup(
    val exerciseId: Uuid,
    val exerciseName: String,
    val sets: List<HistorySessionSetLine>,
) {
    val volume: Double get() = sets.sumOf { it.volume }
}

data class HistorySessionDetail(
    val sessionId: Uuid,
    val title: String,
    val completedAtEpochMillis: Long,
    val scheduleDate: CalendarDate,
    val sessionNote: String?,
    val exerciseGroups: List<HistorySessionExerciseGroup>,
) {
    val totalVolume: Double get() = exerciseGroups.sumOf { it.volume }
}

/** Ported from `Data/Repositories/HistoryRepository.swift`. */
class HistoryRepository(private val db: SetBuddyDatabase) {
    private val q = db.setBuddyQueries

    fun completedRows(limit: Long = 50): List<HistoryCompletedRow> =
        q.selectCompletedSessionsOrderedByRecency(limit).executeAsList().map { session ->
            val loggedSets = q.selectLoggedSetsForSession(session.id).executeAsList()
            val volume = loggedSets.sumOf {
                VolumeCalculator.setVolume(it.weight, it.reps.toInt(), it.repsArePerSide == 1L)
            }
            HistoryCompletedRow(
                sessionId = Uuid.parse(session.id),
                title = session.workoutTitleSnapshot ?: "Workout",
                completedAtEpochMillis = session.completedAt ?: 0,
                totalVolume = volume,
                hasSessionNote = !session.sessionNote.isNullOrBlank(),
            )
        }

    fun sessionDetail(sessionId: Uuid): HistorySessionDetail? {
        val session = q.selectSessionById(sessionId.toString()).executeAsOneOrNull() ?: return null
        val loggedSets = q.selectLoggedSetsForSession(sessionId.toString()).executeAsList()
        val exerciseNames = mutableMapOf<String, String>()
        fun name(exerciseId: String): String =
            exerciseNames.getOrPut(exerciseId) {
                q.selectExerciseById(exerciseId).executeAsOneOrNull()?.name ?: "Exercise"
            }

        val groups = loggedSets.groupBy { it.exerciseId }.map { (exerciseId, sets) ->
            HistorySessionExerciseGroup(
                exerciseId = Uuid.parse(exerciseId),
                exerciseName = name(exerciseId),
                sets = sets.sortedBy { it.setIndex }.map {
                    HistorySessionSetLine(it.setIndex.toInt(), it.weight, it.reps.toInt(), it.repsArePerSide == 1L)
                },
            )
        }

        return HistorySessionDetail(
            sessionId = Uuid.parse(session.id),
            title = session.workoutTitleSnapshot ?: "Workout",
            completedAtEpochMillis = session.completedAt ?: 0,
            scheduleDate = CalendarDate(session.scheduleYear.toInt(), session.scheduleMonth.toInt(), session.scheduleDay.toInt()),
            sessionNote = session.sessionNote,
            exerciseGroups = groups,
        )
    }

    fun allCompletedSessionDetails(): List<HistorySessionDetail> =
        completedRows(limit = Long.MAX_VALUE).mapNotNull { sessionDetail(it.sessionId) }
}

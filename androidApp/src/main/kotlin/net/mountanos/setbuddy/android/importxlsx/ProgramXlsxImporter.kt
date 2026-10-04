package net.mountanos.setbuddy.android.importxlsx

import net.mountanos.setbuddy.domain.CalendarDate
import net.mountanos.setbuddy.domain.ExerciseKind
import net.mountanos.setbuddy.domain.ImportExerciseRef
import net.mountanos.setbuddy.domain.ImportedCycleDay
import net.mountanos.setbuddy.shared.db.SetBuddyDatabase
import kotlin.uuid.Uuid

/** Ported from `Data/Import/ProgramXlsxImporter.swift`. */
class ProgramXlsxImporter(private val db: SetBuddyDatabase) {
    private val q = db.setBuddyQueries

    /**
     * Wipes any existing program (workouts/exercises/schedule cascade) and builds a fresh one from [cycle],
     * matching iOS's `importReplacingStore(cycle:...)`. Completed sessions survive (snapshot-preserved history);
     * in-progress sessions are dropped since their template is about to disappear.
     *
     * @param cycleStartIndex which [cycle] entry (0-based, workbook tab order) lands on [startDate].
     * @param exerciseCarryover pre-resolved (sheet, exercise name) -> existing exercise id map — the caller
     *        (staging UI) is responsible for computing this via `ExerciseCarryoverMatcher` before calling in.
     */
    fun importReplacingStore(
        cycle: List<ImportedCycleDay>,
        programName: String,
        startDate: CalendarDate,
        horizonDays: Int = 196,
        cycleStartIndex: Int = 0,
        exerciseCarryover: Map<ImportExerciseRef, Uuid> = emptyMap(),
    ) {
        val period = cycle.size
        if (period == 0) throw ProgramImportError.EmptyProgram

        val programId = Uuid.random().toString()
        val workoutIdBySheet = mutableMapOf<String, String>()
        // A sheet can repeat an exercise name (e.g. a copy-paste duplicate); both rows then resolve to the same
        // carried-over id, which would violate Exercise's primary key. Only the first keeps it.
        val carriedOverIds = mutableSetOf<Uuid>()

        // One transaction with the wipe, so a failed import rolls back instead of leaving no program at all.
        db.transaction {
            removeAllProgramsPreservingCompletedHistory()

            val nextOrder = q.nextProgramRowOrder().executeAsOne()
            q.insertProgram(programId, programName, nextOrder)

            for (day in cycle) {
                if (day.isRestDay) continue
                if (workoutIdBySheet.containsKey(day.sheetName)) continue
                val workoutId = Uuid.random().toString()
                // First-encountered order in the cycle (interleaved, e.g. Push 1, Cardio 1, Pull 1, ...) — drives
                // display/picker order instead of WorkoutTemplateDisplaySort's Push/Pull/Legs-only naming
                // heuristic, which otherwise groups anything else (like Cardio) at the end.
                q.insertWorkout(workoutId, programId, day.sheetName, workoutIdBySheet.size.toLong())
                day.exercises.forEachIndexed { index, ex ->
                    val ref = ImportExerciseRef(day.sheetName, ex.name)
                    val carriedOverId = exerciseCarryover[ref]?.takeIf { carriedOverIds.add(it) }
                    val exerciseId = (carriedOverId ?: Uuid.random()).toString()
                    // Cardio defaults to a single set (one duration/heart-rate reading), not the strength default.
                    val setCount = if (ex.kind == ExerciseKind.Cardio) 1 else ProgramXlsxParser.DEFAULT_SET_COUNT_PER_EXERCISE
                    q.insertExercise(
                        exerciseId, workoutId, ex.name, index.toLong(), setCount.toLong(),
                        ex.note, if (ex.repsArePerSide) 1L else 0L, ex.kind.rawValue,
                    )
                }
                workoutIdBySheet[day.sheetName] = workoutId
            }

            val startIdx = ((cycleStartIndex % period) + period) % period
            for (h in 0 until horizonDays) {
                val slot = cycle[(h + startIdx) % period]
                val date = startDate.addingDays(h)
                val workoutId = if (slot.isRestDay) null else workoutIdBySheet[slot.sheetName]
                if (!slot.isRestDay && workoutId == null) continue
                q.upsertScheduleEntry(
                    id = Uuid.random().toString(),
                    programId = programId,
                    year = date.year.toLong(),
                    month = date.month.toLong(),
                    day = date.day.toLong(),
                    isRestDay = if (slot.isRestDay) 1L else 0L,
                    workoutId = workoutId,
                )
            }
        }
    }

    /** Backfills `workoutTitleSnapshot`, deletes incomplete sessions, then wipes all programs (cascades). */
    private fun removeAllProgramsPreservingCompletedHistory() {
        val activeProgram = q.selectActiveProgram().executeAsOneOrNull()
        val titles: Map<String, String> = activeProgram?.let { program ->
            q.selectWorkoutsForProgram(program.id).executeAsList().associate { it.id to it.name }
        } ?: emptyMap()

        db.transaction {
            for (session in q.selectSessionsWithMissingSnapshot().executeAsList()) {
                titles[session.workoutTemplateId]?.let { title ->
                    q.updateSessionTitleSnapshot(title, session.id)
                }
            }
            q.deleteIncompleteSessions()
            q.deleteAllPrograms()
        }
    }
}

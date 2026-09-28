package net.mountanos.setbuddy.domain

import kotlin.uuid.Uuid

/**
 * Identifies one exercise in a freshly parsed workbook, before it's persisted — used as the key for carrying an
 * existing exercise's id (and therefore its logged history) onto the matching new one.
 */
data class ImportExerciseRef(val workoutSheetName: String, val exerciseName: String)

/** One exercise entry as it appears in a freshly parsed workbook day. */
data class ImportedCycleExercise(val name: String, val note: String? = null, val repsArePerSide: Boolean = false)

/** One day of a freshly parsed workbook cycle. */
data class ImportedCycleDay(
    val sheetName: String,
    val isRestDay: Boolean,
    val exercises: List<ImportedCycleExercise>,
)

/**
 * Matches exercises from a program about to be replaced against a newly parsed workbook, by name, so a re-import
 * doesn't sever the "reference weight" trail shown while logging (reference lookups key off exercise id, which is
 * otherwise regenerated fresh on every import).
 */
object ExerciseCarryoverMatcher {
    /** Below this similarity, two names are treated as unrelated exercises. */
    const val FUZZY_THRESHOLD = 0.75

    data class ExistingExercise(val id: Uuid, val name: String)

    /** A close-but-not-exact name match, offered to the user to confirm before it's applied. */
    data class Suggestion(
        val newExercise: ImportExerciseRef,
        val oldExerciseId: Uuid,
        val oldExerciseName: String,
        val id: Uuid = Uuid.random(),
    )

    data class Result(
        /** Exact (case/whitespace-insensitive) name matches — applied without asking. */
        val autoCarryover: Map<ImportExerciseRef, Uuid> = emptyMap(),
        /** Close matches (>= [FUZZY_THRESHOLD], < 1.0) — shown to the user, in workbook order, to confirm or reject. */
        val suggestions: List<Suggestion> = emptyList(),
    )

    /**
     * @param existing Exercises from the program about to be replaced (pass empty if there is none).
     * @param newCycle The freshly parsed workbook.
     */
    fun match(existing: List<ExistingExercise>, newCycle: List<ImportedCycleDay>): Result {
        val newRefs = newCycle.filterNot { it.isRestDay }
            .flatMap { day -> day.exercises.map { ex -> ImportExerciseRef(day.sheetName, ex.name) } }

        val remainingOld = existing.toMutableList()
        val autoCarryover = mutableMapOf<ImportExerciseRef, Uuid>()

        // Pass 1: exact matches, greedy in workbook order — each old exercise can be claimed at most once.
        val unmatchedNew = mutableListOf<ImportExerciseRef>()
        for (ref in newRefs) {
            val index = remainingOld.indexOfFirst { normalized(it.name) == normalized(ref.exerciseName) }
            if (index >= 0) {
                autoCarryover[ref] = remainingOld[index].id
                remainingOld.removeAt(index)
            } else {
                unmatchedNew.add(ref)
            }
        }

        // Pass 2: close matches — score every remaining pair, then greedily assign highest-similarity pairs first
        // so one old exercise isn't suggested for two different new ones.
        data class Candidate(val newIndex: Int, val oldIndex: Int, val score: Double)
        val candidates = mutableListOf<Candidate>()
        unmatchedNew.forEachIndexed { newIndex, ref ->
            remainingOld.forEachIndexed { oldIndex, old ->
                val score = StringSimilarity.ratio(normalized(ref.exerciseName), normalized(old.name))
                if (score >= FUZZY_THRESHOLD) {
                    candidates.add(Candidate(newIndex, oldIndex, score))
                }
            }
        }
        candidates.sortByDescending { it.score }

        val claimedOld = mutableSetOf<Int>()
        val claimedNew = mutableSetOf<Int>()
        val suggestions = mutableListOf<Suggestion>()
        for (candidate in candidates) {
            if (candidate.oldIndex in claimedOld || candidate.newIndex in claimedNew) continue
            claimedOld.add(candidate.oldIndex)
            claimedNew.add(candidate.newIndex)
            val ref = unmatchedNew[candidate.newIndex]
            val old = remainingOld[candidate.oldIndex]
            suggestions.add(Suggestion(ref, old.id, old.name))
        }

        // Present in workbook order rather than by-score.
        val order = newRefs.withIndex().associate { (i, ref) -> ref to i }
        suggestions.sortBy { order[it.newExercise] ?: 0 }

        return Result(autoCarryover, suggestions)
    }

    private fun normalized(s: String): String = s.trim().lowercase()
}

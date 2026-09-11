//
//  ExerciseCarryoverMatcher.swift
//  Set Buddy
//

import Foundation

/// Identifies one exercise in the freshly parsed workbook, before it's persisted — used as the key for carrying an
/// existing exercise's id (and therefore its logged history) onto the matching new one.
struct ImportExerciseRef: Hashable, Sendable {
    let workoutSheetName: String
    let exerciseName: String
}

/// Matches exercises from a program about to be replaced against the newly parsed workbook, by name, so a
/// re-import doesn't sever the "reference weight" trail shown while logging (`WorkoutLoggingViewModel`'s previous-
/// session hints key off `PersistedExercise.id`, which is otherwise regenerated fresh on every import).
enum ExerciseCarryoverMatcher {
    /// Below this similarity, two names are treated as unrelated exercises.
    static let fuzzyThreshold = 0.75

    struct ExistingExercise: Sendable {
        let id: UUID
        let name: String
    }

    /// A close-but-not-exact name match, offered to the user to confirm before it's applied.
    struct Suggestion: Identifiable, Sendable {
        let id = UUID()
        let newExercise: ImportExerciseRef
        let oldExerciseId: UUID
        let oldExerciseName: String
    }

    struct Result: Sendable {
        /// Exact (case/whitespace-insensitive) name matches — applied without asking.
        var autoCarryover: [ImportExerciseRef: UUID] = [:]
        /// Close matches (`>= fuzzyThreshold`, `< 1.0`) — shown to the user, in workbook order, to confirm or reject.
        var suggestions: [Suggestion] = []
    }

    /// - Parameters:
    ///   - existing: Exercises from the program about to be replaced (ignored if there is none).
    ///   - newCycle: The freshly parsed workbook.
    static func match(existing: [ExistingExercise], newCycle: [XlsxCycleDay]) -> Result {
        var newRefs: [ImportExerciseRef] = []
        for day in newCycle where !day.isRestDay {
            for exercise in day.exercises {
                newRefs.append(ImportExerciseRef(workoutSheetName: day.sheetName, exerciseName: exercise.name))
            }
        }

        var remainingOld = existing
        var result = Result()

        // Pass 1: exact matches, greedy in workbook order — each old exercise can be claimed at most once.
        var unmatchedNew: [ImportExerciseRef] = []
        for ref in newRefs {
            if let index = remainingOld.firstIndex(where: { normalized($0.name) == normalized(ref.exerciseName) }) {
                result.autoCarryover[ref] = remainingOld[index].id
                remainingOld.remove(at: index)
            } else {
                unmatchedNew.append(ref)
            }
        }

        // Pass 2: close matches — score every remaining pair, then greedily assign highest-similarity pairs first
        // so one old exercise isn't suggested for two different new ones.
        struct Candidate { let newIndex: Int; let oldIndex: Int; let score: Double }
        var candidates: [Candidate] = []
        for (newIndex, ref) in unmatchedNew.enumerated() {
            for (oldIndex, old) in remainingOld.enumerated() {
                let score = StringSimilarity.ratio(normalized(ref.exerciseName), normalized(old.name))
                if score >= fuzzyThreshold {
                    candidates.append(Candidate(newIndex: newIndex, oldIndex: oldIndex, score: score))
                }
            }
        }
        candidates.sort { $0.score > $1.score }

        var claimedOldIndices = Set<Int>()
        var claimedNewIndices = Set<Int>()
        for candidate in candidates {
            guard !claimedOldIndices.contains(candidate.oldIndex), !claimedNewIndices.contains(candidate.newIndex) else { continue }
            claimedOldIndices.insert(candidate.oldIndex)
            claimedNewIndices.insert(candidate.newIndex)
            let ref = unmatchedNew[candidate.newIndex]
            let old = remainingOld[candidate.oldIndex]
            result.suggestions.append(Suggestion(newExercise: ref, oldExerciseId: old.id, oldExerciseName: old.name))
        }

        // Present in workbook order rather than by-score.
        let order = Dictionary(uniqueKeysWithValues: newRefs.enumerated().map { ($1, $0) })
        result.suggestions.sort { (order[$0.newExercise] ?? 0) < (order[$1.newExercise] ?? 0) }

        return result
    }

    private static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

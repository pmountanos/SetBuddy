//
//  WorkoutSessionRepository.swift
//  Set Buddy
//

import Foundation
import SwiftData

@MainActor
struct WorkoutSessionRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func workout(templateId: UUID) throws -> PersistedWorkout? {
        try modelContext.first(PersistedWorkout.self, matching: #Predicate<PersistedWorkout> { $0.id == templateId })
    }

    func activeSession(templateId: UUID, day: CalendarDate) throws -> PersistedWorkoutSession? {
        let year = day.year, month = day.month, dayNum = day.day
        return try modelContext.first(
            PersistedWorkoutSession.self,
            matching: #Predicate<PersistedWorkoutSession> { session in
                session.workoutTemplateId == templateId
                    && session.scheduleYear == year
                    && session.scheduleMonth == month
                    && session.scheduleDay == dayNum
                    && !session.isComplete
            }
        )
    }

    /// Whether this template already has a **completed** session on the given calendar day.
    func hasCompletedSession(templateId: UUID, day: CalendarDate) throws -> Bool {
        let year = day.year, month = day.month, dayNum = day.day
        let match = try modelContext.first(
            PersistedWorkoutSession.self,
            matching: #Predicate<PersistedWorkoutSession> { session in
                session.workoutTemplateId == templateId
                    && session.scheduleYear == year
                    && session.scheduleMonth == month
                    && session.scheduleDay == dayNum
                    && session.isComplete
            }
        )
        return match != nil
    }

    func getOrCreateActiveSession(templateId: UUID, day: CalendarDate, workout: PersistedWorkout) throws -> PersistedWorkoutSession {
        let session: PersistedWorkoutSession
        if let existing = try activeSession(templateId: templateId, day: day) {
            session = existing
        } else {
            session = PersistedWorkoutSession(
                workoutTemplateId: templateId,
                scheduleYear: day.year,
                scheduleMonth: day.month,
                scheduleDay: day.day
            )
            modelContext.insert(session)
        }
        populateMissingLoggedSets(session: session, workout: workout)
        try pruneLoggedSetsExceedingTemplate(session: session, workout: workout)
        syncRepsArePerSideFromTemplate(session: session, workout: workout)
        try modelContext.save()
        return session
    }

    /// Most recent logged value for each (exercise, set position), across **all** completed sessions regardless of
    /// workout — not just the current workout template. Scoping by exercise id rather than workout id is what keeps
    /// `WorkoutLoggingViewModel`'s reference-weight hints working after a program re-import: exercises carried over
    /// by `ExerciseCarryoverMatcher` keep their id, so their logged history is still found here even though the
    /// workout template that originally held them was replaced.
    func mostRecentLoggedValuesByExercise() throws -> [UUID: [Int: PersistedLoggedSet]] {
        let sessions = try modelContext.fetch(FetchDescriptor<PersistedWorkoutSession>(
            predicate: #Predicate<PersistedWorkoutSession> { $0.isComplete }
        ))
        var bestDate: [UUID: [Int: Date]] = [:]
        var best: [UUID: [Int: PersistedLoggedSet]] = [:]
        for session in sessions {
            let sessionDate = session.completedAt ?? session.createdAt
            for row in session.loggedSets {
                if let existing = bestDate[row.exerciseId]?[row.setIndex], existing >= sessionDate { continue }
                bestDate[row.exerciseId, default: [:]][row.setIndex] = sessionDate
                best[row.exerciseId, default: [:]][row.setIndex] = row
            }
        }
        return best
    }

    /// Records a user-entered set value; only ever called with `markUserEntry == true` at the call site.
    func updateLoggedSet(session: PersistedWorkoutSession, exerciseId: UUID, setIndex: Int, weight: Double, reps: Int) throws {
        guard let logged = session.loggedSets.first(where: { $0.exerciseId == exerciseId && $0.setIndex == setIndex }) else { return }
        logged.weight = max(0, weight)
        logged.reps = max(0, reps)
        logged.userEditedValues = true
        try modelContext.save()
    }

    /// Drops rows the user never entered, snapshots the workout title, and marks the session complete.
    func completeSession(_ session: PersistedWorkoutSession, workoutTitle: String) throws {
        for logged in session.loggedSets where !logged.userEditedValues {
            modelContext.delete(logged)
        }
        session.workoutTitleSnapshot = workoutTitle
        session.isComplete = true
        session.completedAt = Date()
        try modelContext.save()
    }

    func setSessionNote(_ session: PersistedWorkoutSession, note: String) throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        session.sessionNote = trimmed.isEmpty ? nil : trimmed
        try modelContext.save()
    }

    /// Creates persisted rows (zero weight/reps) for any exercise/set the session doesn't already have a row for —
    /// covers both a brand-new session (no rows yet) and the template gaining sets (e.g. 3 → 4) while one is in progress.
    private func populateMissingLoggedSets(session: PersistedWorkoutSession, workout: PersistedWorkout) {
        let ordered = workout.exercises.sorted { $0.sortOrder < $1.sortOrder }
        for exercise in ordered {
            for setIdx in 0 ..< exercise.setCount {
                let exists = session.loggedSets.contains { $0.exerciseId == exercise.id && $0.setIndex == setIdx }
                if exists { continue }
                let row = PersistedLoggedSet(
                    exerciseId: exercise.id,
                    setIndex: setIdx,
                    weight: 0,
                    reps: 0,
                    seededFromCarryover: false,
                    repsArePerSide: exercise.repsArePerSide
                )
                row.session = session
                session.loggedSets.append(row)
            }
        }
    }

    /// Keeps logged rows aligned with the template’s per-side flag (e.g. after re-import or edit).
    private func syncRepsArePerSideFromTemplate(session: PersistedWorkoutSession, workout: PersistedWorkout) {
        let byId = Dictionary(uniqueKeysWithValues: workout.exercises.map { ($0.id, $0) })
        for row in session.loggedSets {
            guard let ex = byId[row.exerciseId] else { continue }
            row.repsArePerSide = ex.repsArePerSide
        }
    }

    /// Drops logged rows past the template `setCount` on **in‑progress** sessions (e.g. after capping at four sets).
    private func pruneLoggedSetsExceedingTemplate(session: PersistedWorkoutSession, workout: PersistedWorkout) throws {
        guard !session.isComplete else { return }
        let ordered = workout.exercises.sorted { $0.sortOrder < $1.sortOrder }
        for exercise in ordered {
            let extras = session.loggedSets.filter { $0.exerciseId == exercise.id && $0.setIndex >= exercise.setCount }
            for row in extras {
                modelContext.delete(row)
            }
        }
    }
}

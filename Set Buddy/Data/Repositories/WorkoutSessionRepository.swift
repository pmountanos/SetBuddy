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
        let all = try modelContext.fetch(FetchDescriptor<PersistedWorkout>())
        return all.first { $0.id == templateId }
    }

    func activeSession(templateId: UUID, day: CalendarDate) throws -> PersistedWorkoutSession? {
        let all = try modelContext.fetch(FetchDescriptor<PersistedWorkoutSession>())
        return all.first {
            $0.workoutTemplateId == templateId
                && $0.scheduleYear == day.year
                && $0.scheduleMonth == day.month
                && $0.scheduleDay == day.day
                && !$0.isComplete
        }
    }

    /// Whether this template already has a **completed** session on the given calendar day.
    func hasCompletedSession(templateId: UUID, day: CalendarDate) throws -> Bool {
        let all = try modelContext.fetch(FetchDescriptor<PersistedWorkoutSession>())
        return all.contains {
            $0.workoutTemplateId == templateId
                && $0.scheduleYear == day.year
                && $0.scheduleMonth == day.month
                && $0.scheduleDay == day.day
                && $0.isComplete
        }
    }

    func getOrCreateActiveSession(templateId: UUID, day: CalendarDate, workout: PersistedWorkout) throws -> PersistedWorkoutSession {
        if let existing = try activeSession(templateId: templateId, day: day) {
            try ensureLoggedSetsPopulated(session: existing, workout: workout)
            try syncAdditionalLoggedSets(session: existing, workout: workout)
            try pruneLoggedSetsExceedingTemplate(session: existing, workout: workout)
            syncRepsArePerSideFromTemplate(session: existing, workout: workout)
            try modelContext.save()
            return existing
        }
        let session = PersistedWorkoutSession(
            workoutTemplateId: templateId,
            scheduleYear: day.year,
            scheduleMonth: day.month,
            scheduleDay: day.day
        )
        modelContext.insert(session)
        populateLoggedSets(session: session, workout: workout)
        try syncAdditionalLoggedSets(session: session, workout: workout)
        try pruneLoggedSetsExceedingTemplate(session: session, workout: workout)
        syncRepsArePerSideFromTemplate(session: session, workout: workout)
        try modelContext.save()
        return session
    }

    /// Latest finished session for this workout template (by completion or creation time).
    func mostRecentCompletedSession(templateId: UUID) throws -> PersistedWorkoutSession? {
        let all = try modelContext.fetch(FetchDescriptor<PersistedWorkoutSession>())
        return all
            .filter { $0.workoutTemplateId == templateId && $0.isComplete }
            .max(by: { a, b in
                let ad = a.completedAt ?? a.createdAt
                let bd = b.completedAt ?? b.createdAt
                return ad < bd
            })
    }

    /// Creates persisted rows with **zero** weight/reps; previous-session values are shown in the UI only until the user enters data.
    private func populateLoggedSets(session: PersistedWorkoutSession, workout: PersistedWorkout) {
        let ordered = workout.exercises.sorted { $0.sortOrder < $1.sortOrder }
        for exercise in ordered {
            for setIdx in 0 ..< exercise.setCount {
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

    private func ensureLoggedSetsPopulated(session: PersistedWorkoutSession, workout: PersistedWorkout) throws {
        if session.loggedSets.isEmpty {
            populateLoggedSets(session: session, workout: workout)
        }
    }

    /// Adds missing logged rows when the template gains sets (e.g. 3 → 4) while a session is in progress.
    private func syncAdditionalLoggedSets(session: PersistedWorkoutSession, workout: PersistedWorkout) throws {
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

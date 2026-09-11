//
//  HistoryRepository.swift
//  Set Buddy
//

import Foundation
import SwiftData

struct HistoryCompletedRow: Identifiable, Sendable {
    let id: UUID
    let completedAt: Date
    let workoutTitle: String
    let volume: Double
    let hasSessionNote: Bool
}

struct HistorySessionSetLine: Identifiable, Sendable {
    var id: String { "\(exerciseId.uuidString)-\(setIndex)" }
    let exerciseId: UUID
    let setIndex: Int
    let setNumber: Int
    let weight: Double
    let reps: Int
    /// When true, volume for this set used the per-side multiplier (×2).
    let repsArePerSide: Bool
}

struct HistorySessionExerciseGroup: Identifiable, Sendable {
    let exerciseId: UUID
    let name: String
    let volume: Double
    let sets: [HistorySessionSetLine]

    var id: UUID { exerciseId }
}

struct HistorySessionDetail: Identifiable, Sendable {
    let id: UUID
    let completedAt: Date
    let workoutTitle: String
    let totalVolume: Double
    /// Calendar day this session was logged under (program schedule).
    let scheduleDayLabel: String?
    /// User workout note (may be empty).
    let sessionNote: String?
    let exercises: [HistorySessionExerciseGroup]
}

@MainActor
struct HistoryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func completedRows(limit: Int = 50) throws -> [HistoryCompletedRow] {
        let workouts = try modelContext.fetch(FetchDescriptor<PersistedWorkout>())
        let titles = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0.name) })
        let sessions = try modelContext.fetch(FetchDescriptor<PersistedWorkoutSession>())
        return sessions
            .filter(\.isComplete)
            .sorted {
                ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt)
            }
            .prefix(limit)
            .map { session in
                let vol = session.loggedSets.reduce(0.0) {
                    $0 + VolumeCalculator.setVolume(weight: $1.weight, reps: $1.reps, repsArePerSide: $1.repsArePerSide)
                }
                let title = session.workoutTitleSnapshot
                    ?? titles[session.workoutTemplateId]
                    ?? "Workout"
                let noteTrimmed = session.sessionNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return HistoryCompletedRow(
                    id: session.id,
                    completedAt: session.completedAt ?? session.createdAt,
                    workoutTitle: title,
                    volume: vol,
                    hasSessionNote: !noteTrimmed.isEmpty
                )
            }
    }

    /// Loads a finished session for history drill-down (sets grouped by exercise).
    func sessionDetail(sessionId: UUID) throws -> HistorySessionDetail? {
        let sessions = try modelContext.fetch(FetchDescriptor<PersistedWorkoutSession>())
        guard let session = sessions.first(where: { $0.id == sessionId && $0.isComplete }) else { return nil }

        let workouts = try modelContext.fetch(FetchDescriptor<PersistedWorkout>())
        let titles = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0.name) })
        let workoutTitle = session.workoutTitleSnapshot
            ?? titles[session.workoutTemplateId]
            ?? "Workout"

        let template = try WorkoutSessionRepository(modelContext: modelContext).workout(templateId: session.workoutTemplateId)
        let logged = session.loggedSets
        let grouped = Dictionary(grouping: logged, by: \.exerciseId)

        var orderedIds: [UUID] = []
        if let template {
            let sortedExercises = template.exercises.sorted { $0.sortOrder < $1.sortOrder }
            for ex in sortedExercises where grouped[ex.id] != nil {
                orderedIds.append(ex.id)
            }
        }
        let known = Set(orderedIds)
        let remaining = grouped.keys.filter { !known.contains($0) }.sorted { a, b in
            let minA = grouped[a]!.map(\.setIndex).min() ?? 0
            let minB = grouped[b]!.map(\.setIndex).min() ?? 0
            if minA != minB { return minA < minB }
            return a.uuidString < b.uuidString
        }
        orderedIds.append(contentsOf: remaining)

        func name(for exerciseId: UUID) -> String {
            guard let template else { return "Exercise" }
            return template.exercises.first(where: { $0.id == exerciseId })?.name ?? "Exercise"
        }

        var exerciseGroups: [HistorySessionExerciseGroup] = []
        var totalVolume = 0.0
        for exerciseId in orderedIds {
            guard let rows = grouped[exerciseId] else { continue }
            let sortedRows = rows.sorted { $0.setIndex < $1.setIndex }
            var exerciseVol = 0.0
            let lines: [HistorySessionSetLine] = sortedRows.enumerated().map { _, row in
                let v = VolumeCalculator.setVolume(weight: row.weight, reps: row.reps, repsArePerSide: row.repsArePerSide)
                exerciseVol += v
                return HistorySessionSetLine(
                    exerciseId: exerciseId,
                    setIndex: row.setIndex,
                    setNumber: row.setIndex + 1,
                    weight: row.weight,
                    reps: row.reps,
                    repsArePerSide: row.repsArePerSide
                )
            }
            totalVolume += exerciseVol
            exerciseGroups.append(
                HistorySessionExerciseGroup(
                    exerciseId: exerciseId,
                    name: name(for: exerciseId),
                    volume: exerciseVol,
                    sets: lines
                )
            )
        }

        let scheduleLabel: String? = {
            let cal = Calendar.current
            var c = DateComponents()
            c.year = session.scheduleYear
            c.month = session.scheduleMonth
            c.day = session.scheduleDay
            guard let date = cal.date(from: c) else { return nil }
            return date.formatted(date: .abbreviated, time: .omitted)
        }()

        let noteTrimmed = session.sessionNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionNote = (noteTrimmed?.isEmpty ?? true) ? nil : noteTrimmed

        return HistorySessionDetail(
            id: session.id,
            completedAt: session.completedAt ?? session.createdAt,
            workoutTitle: workoutTitle,
            totalVolume: totalVolume,
            scheduleDayLabel: scheduleLabel,
            sessionNote: sessionNote,
            exercises: exerciseGroups
        )
    }

    /// All completed sessions, newest first (for export).
    func allCompletedSessionDetails() throws -> [HistorySessionDetail] {
        let sessions = try modelContext.fetch(FetchDescriptor<PersistedWorkoutSession>())
        let completed = sessions
            .filter(\.isComplete)
            .sorted {
                ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt)
            }
        return try completed.compactMap { try sessionDetail(sessionId: $0.id) }
    }
}

//
//  ProgramOutlineRepository.swift
//  Set Buddy
//

import Foundation
import SwiftData

struct ProgramExerciseOutline: Identifiable, Sendable {
    let id: UUID
    let name: String
    let note: String?
    /// Loggable sets for this exercise (import default 4; editable in app).
    let setCount: Int
    /// Imported / template flag: reps logged per side (volume ×2).
    let repsArePerSide: Bool
    /// Strength (weight/reps) or cardio (minutes/max heart rate).
    let kind: ExerciseKind

    var hasNonEmptyNote: Bool {
        !(note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

struct ProgramWorkoutOutline: Identifiable, Sendable {
    let id: UUID
    let name: String
    let exercises: [ProgramExerciseOutline]
}

struct ProgramOutline: Sendable {
    let programName: String
    let workouts: [ProgramWorkoutOutline]
}

/// One row in the Program tab’s upcoming calendar (workout vs rest).
struct ProgramScheduleDayRow: Identifiable, Sendable {
    let date: CalendarDate
    let dateLabel: String
    let subtitle: String
    let isRestDay: Bool
    /// Set for workout days so the user can open the template editor from the schedule.
    let workoutTemplateId: UUID?

    var id: String { "\(date.year)-\(date.month)-\(date.day)" }
}

@MainActor
struct ProgramOutlineRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func activeProgramOutline() throws -> ProgramOutline? {
        var descriptor = FetchDescriptor<PersistedProgram>()
        descriptor.fetchLimit = 1
        guard let program = try modelContext.fetch(descriptor).first else { return nil }
        // sortOrder (import/cycle position) first; falls back to the naming heuristic on ties (e.g. every
        // workout still at the default 0 on an install that predates this field, until it's re-imported).
        let sortedWorkouts = program.workouts.sorted { a, b in
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return WorkoutTemplateDisplaySort.compare(a.name, b.name)
        }
        let outlines = sortedWorkouts.map { workout in
            let exercises = workout.exercises
                .sorted { $0.sortOrder < $1.sortOrder }
                .map {
                    ProgramExerciseOutline(
                        id: $0.id,
                        name: $0.name,
                        note: $0.note,
                        setCount: $0.setCount,
                        repsArePerSide: $0.repsArePerSide,
                        kind: $0.kind
                    )
                }
            return ProgramWorkoutOutline(id: workout.id, name: workout.name, exercises: exercises)
        }
        return ProgramOutline(programName: program.name, workouts: outlines)
    }

    /// Schedule entries on or after today, sorted, capped at `limit` (e.g. next 14 days on the program calendar).
    func upcomingScheduleRows(limit: Int, calendar: Calendar) throws -> [ProgramScheduleDayRow] {
        var descriptor = FetchDescriptor<PersistedProgram>()
        descriptor.fetchLimit = 1
        guard let program = try modelContext.fetch(descriptor).first else { return [] }

        let titles = ProgramRepository(modelContext: modelContext).workoutTitles(for: program)
        let today = CalendarDate(from: Date(), calendar: calendar)

        return Array(
            program.scheduleEntries
                .map { entry -> (CalendarDate, PersistedScheduleEntry) in
                    let cd = CalendarDate(year: entry.year, month: entry.month, day: entry.day)
                    return (cd, entry)
                }
                .filter { $0.0 >= today }
                .sorted { $0.0 < $1.0 }
                .prefix(limit)
                .map { cd, entry in
                    let dateLabel: String
                    if let d = cd.startOfDay(using: calendar) {
                        dateLabel = d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    } else {
                        dateLabel = "\(cd.month)/\(cd.day)/\(cd.year)"
                    }
                    let subtitle: String
                    let isRest: Bool
                    let templateId: UUID?
                    if entry.isRestDay {
                        subtitle = "Rest"
                        isRest = true
                        templateId = nil
                    } else if let wid = entry.workoutID, let name = titles[wid] {
                        subtitle = name
                        isRest = false
                        templateId = wid
                    } else {
                        subtitle = "Workout"
                        isRest = false
                        templateId = entry.workoutID
                    }
                    return ProgramScheduleDayRow(
                        date: cd,
                        dateLabel: dateLabel,
                        subtitle: subtitle,
                        isRestDay: isRest,
                        workoutTemplateId: templateId
                    )
                }
        )
    }
}

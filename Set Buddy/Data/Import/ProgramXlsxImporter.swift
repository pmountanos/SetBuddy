//
//  ProgramXlsxImporter.swift
//  Set Buddy
//

import Foundation
import SwiftData

@MainActor
enum ProgramXlsxImporter {
    /// Replaces the active program and schedule from the workbook.
    ///
    /// **Completed** workout sessions (and their sets/volume) are kept for history.
    /// In-progress sessions are removed so they do not reference deleted templates.
    ///
    /// - Parameters:
    ///   - xlsx: Raw `.xlsx` workbook data (one worksheet per cycle day).
    ///   - programName: Title stored on the new `PersistedProgram`.
    ///   - startDate: Calendar day mapped to the chosen cycle position (`cycleStartIndex`).
    ///   - modelContext: SwiftData context used for deletes and inserts.
    ///   - calendar: Calendar used when advancing `startDate` by day for each horizon slot.
    ///   - horizonDays: Number of forward calendar days to materialize; defaults to `ProgramRepository.forwardScheduleHorizonDays` (~28 weeks).
    ///   - cycleStartIndex: Which workbook day (0 = first tab in order) maps to `startDate`; progression continues in tab order.
    static func importReplacingStore(
        xlsx: Data,
        programName: String,
        startDate: CalendarDate,
        modelContext: ModelContext,
        calendar: Calendar = .current,
        horizonDays: Int = ProgramRepository.forwardScheduleHorizonDays,
        cycleStartIndex: Int = 0,
        exerciseCarryover: [ImportExerciseRef: UUID] = [:]
    ) throws {
        let cycle = try ProgramXlsxParser.parse(xlsxData: xlsx)
        try importReplacingStore(
            cycle: cycle,
            programName: programName,
            startDate: startDate,
            modelContext: modelContext,
            calendar: calendar,
            horizonDays: horizonDays,
            cycleStartIndex: cycleStartIndex,
            exerciseCarryover: exerciseCarryover
        )
    }

    /// Same as the `xlsx:` overload, but for callers (like the Settings import staging flow) that already parsed the
    /// workbook once to show the cycle picker and don't need to parse it again to import.
    ///
    /// - Parameter exerciseCarryover: New exercise (workout sheet + name) → id of the matching exercise from the
    ///   program being replaced, from `ExerciseCarryoverMatcher`. The new `PersistedExercise` reuses that id instead
    ///   of a fresh one, so `WorkoutLoggingViewModel`'s previous-session reference values keep working across the
    ///   re-import for exercises the user is still doing.
    static func importReplacingStore(
        cycle: [XlsxCycleDay],
        programName: String,
        startDate: CalendarDate,
        modelContext: ModelContext,
        calendar: Calendar = .current,
        horizonDays: Int = ProgramRepository.forwardScheduleHorizonDays,
        cycleStartIndex: Int = 0,
        exerciseCarryover: [ImportExerciseRef: UUID] = [:]
    ) throws {
        try removeAllProgramsPreservingCompletedHistory(modelContext: modelContext)

        let program = PersistedProgram(name: programName)
        modelContext.insert(program)

        var workoutBySheet: [String: PersistedWorkout] = [:]
        for day in cycle where !day.isRestDay {
            if workoutBySheet[day.sheetName] != nil { continue }
            let w = PersistedWorkout(name: day.sheetName)
            w.program = program
            program.workouts.append(w)
            for (index, ex) in day.exercises.enumerated() {
                let ref = ImportExerciseRef(workoutSheetName: day.sheetName, exerciseName: ex.name)
                let pe = PersistedExercise(
                    id: exerciseCarryover[ref] ?? UUID(),
                    name: ex.name,
                    sortOrder: index,
                    setCount: ProgramXlsxParser.defaultSetCountPerExercise,
                    note: ex.note,
                    repsArePerSide: ex.repsArePerSide,
                    kind: ex.kind
                )
                pe.workout = w
                w.exercises.append(pe)
            }
            workoutBySheet[day.sheetName] = w
        }

        let period = cycle.count
        guard period > 0 else { throw ProgramImportError.emptyProgram }
        let startIdx = ((cycleStartIndex % period) + period) % period

        for h in 0 ..< horizonDays {
            let slot = cycle[(h + startIdx) % period]
            guard let cd = startDate.addingDays(h, calendar: calendar) else { continue }
            if slot.isRestDay {
                let entry = PersistedScheduleEntry(
                    year: cd.year,
                    month: cd.month,
                    day: cd.day,
                    isRestDay: true,
                    workoutID: nil
                )
                entry.program = program
                program.scheduleEntries.append(entry)
            } else if let w = workoutBySheet[slot.sheetName] {
                let entry = PersistedScheduleEntry(
                    year: cd.year,
                    month: cd.month,
                    day: cd.day,
                    isRestDay: false,
                    workoutID: w.id
                )
                entry.program = program
                program.scheduleEntries.append(entry)
            }
        }

        try modelContext.save()
    }

    /// Same history-safe teardown as import: snapshot workout titles on completed sessions, delete in-progress sessions, delete all programs.
    /// - Parameter modelContext: SwiftData context whose programs (and related incomplete sessions) are cleared.
    static func removeAllProgramsPreservingCompletedHistory(modelContext: ModelContext) throws {
        try prepareStoreForProgramImport(modelContext: modelContext)
        try deleteAllPrograms(modelContext: modelContext)
    }

    /// Ensures completed sessions have a title snapshot (for history after templates are replaced), then drops in-progress sessions.
    private static func prepareStoreForProgramImport(modelContext: ModelContext) throws {
        try backfillWorkoutTitleSnapshots(modelContext: modelContext)
        try deleteIncompleteSessions(modelContext: modelContext)
        try modelContext.save()
    }

    private static func backfillWorkoutTitleSnapshots(modelContext: ModelContext) throws {
        let repo = ProgramRepository(modelContext: modelContext)
        let titles = try repo.activeProgram().map { repo.workoutTitles(for: $0) } ?? [:]
        let sessions = try modelContext.fetch(FetchDescriptor<PersistedWorkoutSession>())
        for session in sessions where session.workoutTitleSnapshot == nil {
            if let name = titles[session.workoutTemplateId] {
                session.workoutTitleSnapshot = name
            }
        }
    }

    private static func deleteIncompleteSessions(modelContext: ModelContext) throws {
        let sessions = try modelContext.fetch(FetchDescriptor<PersistedWorkoutSession>())
        for session in sessions where !session.isComplete {
            modelContext.delete(session)
        }
    }

    private static func deleteAllPrograms(modelContext: ModelContext) throws {
        let programs = try modelContext.fetch(FetchDescriptor<PersistedProgram>())
        programs.forEach { modelContext.delete($0) }
        try modelContext.save()
    }
}

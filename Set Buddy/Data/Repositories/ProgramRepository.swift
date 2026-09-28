//
//  ProgramRepository.swift
//  Set Buddy
//

import Foundation
import SwiftData

/// Assignment for one day on the program calendar (rest vs a workout template). Editable in-app like import.
enum ProgramDaySchedulePickerValue: Hashable, Sendable {
    case rest
    case workout(UUID)
}

@MainActor
struct ProgramRepository {
    /// Days of calendar rows kept ahead of today (rest until assigned); matches spreadsheet import horizon.
    /// `nonisolated` so Swift 6 can use this value in default arguments and other nonisolated contexts.
    nonisolated static let forwardScheduleHorizonDays = 196
    /// How many days ahead `setScheduleDayShiftingFollowing` looks for `value` already recurring, to swap to it
    /// (bounded rotation) instead of inserting a duplicate and shifting the whole remaining horizon. Generous
    /// upper bound on realistic workout-rotation cycle lengths — long enough to catch any real cycle, short
    /// enough that a coincidental match far in the future doesn't get treated as "the same upcoming slot."
    nonisolated static let nearDuplicateSearchWindow = 60

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func activeProgram() throws -> PersistedProgram? {
        var descriptor = FetchDescriptor<PersistedProgram>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func calendarSchedule(for program: PersistedProgram) -> ProgramCalendarSchedule {
        var schedule = ProgramCalendarSchedule()
        for entry in program.scheduleEntries {
            let date = CalendarDate(year: entry.year, month: entry.month, day: entry.day)
            if entry.isRestDay {
                schedule.set(.rest, on: date)
            } else if let wid = entry.workoutID {
                schedule.set(.workout(workoutId: wid), on: date)
            }
        }
        return schedule
    }

    func workoutTitles(for program: PersistedProgram) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: program.workouts.map { ($0.id, $0.name) })
    }

    /// Inserts each missing day in `[today, today + horizon)` as a **rest** row so schedule pickers and Today always have data (safe to call repeatedly).
    func ensureForwardScheduleFilled(calendar: Calendar = .current, daysAhead: Int? = nil) throws {
        let horizon = daysAhead ?? Self.forwardScheduleHorizonDays
        guard let program = try activeProgram() else { return }
        var existing = Set(program.scheduleEntries.map {
            CalendarDate(year: $0.year, month: $0.month, day: $0.day)
        })
        let start = calendar.startOfDay(for: Date())
        var added = false
        for offset in 0 ..< horizon {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let cd = CalendarDate(from: date, calendar: calendar)
            guard !existing.contains(cd) else { continue }
            let entry = PersistedScheduleEntry(
                year: cd.year,
                month: cd.month,
                day: cd.day,
                isRestDay: true,
                workoutID: nil
            )
            entry.program = program
            program.scheduleEntries.append(entry)
            modelContext.insert(entry)
            existing.insert(cd)
            added = true
        }
        if added {
            try modelContext.save()
        }
    }

    /// Creates the only program when the store is empty: one starter workout with one exercise, plus a forward schedule (all rest until you assign workouts in Program).
    func createFirstProgram(name: String, calendar: Calendar = .current) throws -> PersistedProgram {
        guard try activeProgram() == nil else {
            throw ProgramEditingError.programAlreadyExists
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let programName = trimmed.isEmpty ? "My program" : trimmed

        let program = PersistedProgram(name: programName)
        let w = PersistedWorkout(name: "Workout 1")
        w.program = program
        program.workouts.append(w)

        let ex = PersistedExercise(
            name: "Exercise 1",
            sortOrder: 0,
            setCount: Self.defaultTemplateSetCount
        )
        ex.workout = w
        w.exercises.append(ex)

        modelContext.insert(program)
        modelContext.insert(w)
        modelContext.insert(ex)
        try modelContext.save()

        try ensureForwardScheduleFilled(calendar: calendar, daysAhead: Self.forwardScheduleHorizonDays)
        return program
    }

    /// Renames stored programs that still use legacy workbook filenames (`Workout Buddy-2`, `Set Buddy-2`, etc.) to Set Buddy.
    static func migrateLegacyImportedProgramTitles(modelContext: ModelContext) throws {
        let programs = try modelContext.fetch(FetchDescriptor<PersistedProgram>())
        var changed = false
        for program in programs {
            guard let newName = ImportedProgramDisplayNaming.normalizedStoredProgramName(program.name) else { continue }
            program.name = newName
            changed = true
        }
        if changed {
            try modelContext.save()
        }
    }

    /// Like spreadsheet import replacement: preserves completed sessions in History (with title snapshots), clears in-progress workouts, removes all programs, then inserts a new starter program.
    func startOverFreshProgram(name: String, calendar: Calendar = .current) throws -> PersistedProgram {
        try ProgramXlsxImporter.removeAllProgramsPreservingCompletedHistory(modelContext: modelContext)
        return try createFirstProgram(name: name, calendar: calendar)
    }

    /// Inserts a demo program and calendar schedule when the store is empty (**UI tests only** — real installs use “Create program” on the Program tab).
    static func seedIfNeeded(modelContext: ModelContext) throws {
        var descriptor = FetchDescriptor<PersistedProgram>()
        descriptor.fetchLimit = 1
        if try modelContext.fetch(descriptor).first != nil {
            return
        }

        let program = PersistedProgram(name: "Sample Program")
        let upper = PersistedWorkout(name: "Upper Day A", sortOrder: 0)
        let lower = PersistedWorkout(name: "Lower Day B", sortOrder: 1)
        upper.program = program
        lower.program = program
        program.workouts.append(contentsOf: [upper, lower])
        Self.attachTemplateExercises(to: upper)
        Self.attachTemplateExercises(to: lower)

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        for offset in 0 ..< Self.forwardScheduleHorizonDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let cd = CalendarDate(from: date, calendar: calendar)
            let isRest = offset % 2 == 1
            let workoutID: UUID? = isRest ? nil : (offset % 4 == 0 ? upper.id : lower.id)
            let entry = PersistedScheduleEntry(
                year: cd.year,
                month: cd.month,
                day: cd.day,
                isRestDay: isRest,
                workoutID: workoutID
            )
            entry.program = program
            program.scheduleEntries.append(entry)
        }

        modelContext.insert(program)
        try modelContext.save()
    }

    /// Adds default exercises to template workouts that have none (covers existing installs after schema upgrades).
    /// Does **not** change `setCount` on existing exercises so import and in-app edits stay intact.
    static func addExerciseTemplatesIfMissing(modelContext: ModelContext) throws {
        let programs = try modelContext.fetch(FetchDescriptor<PersistedProgram>())
        guard let program = programs.first else { return }
        var changed = false
        for workout in program.workouts where workout.exercises.isEmpty {
            Self.attachTemplateExercises(to: workout)
            changed = true
        }
        if changed {
            try modelContext.save()
        }
    }

    private static let defaultTemplateSetCount = 4

    private static func attachTemplateExercises(to workout: PersistedWorkout) {
        let templates: [(String, Int)]
        if workout.name.localizedCaseInsensitiveContains("upper") {
            templates = [("Bench Press", defaultTemplateSetCount), ("Barbell Row", defaultTemplateSetCount), ("Overhead Press", defaultTemplateSetCount)]
        } else if workout.name.localizedCaseInsensitiveContains("lower") {
            templates = [("Back Squat", defaultTemplateSetCount), ("Romanian Deadlift", defaultTemplateSetCount), ("Leg Curl", defaultTemplateSetCount)]
        } else {
            templates = [("Main lift", defaultTemplateSetCount), ("Accessory", defaultTemplateSetCount)]
        }
        for (index, pair) in templates.enumerated() {
            let ex = PersistedExercise(name: pair.0, sortOrder: index, setCount: pair.1)
            ex.workout = workout
            workout.exercises.append(ex)
        }
    }

    // MARK: - In-app program editing (parity with spreadsheet import)

    func renameProgram(to name: String) throws {
        guard let program = try activeProgram() else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        program.name = trimmed
        try modelContext.save()
    }

    func renameWorkout(id: UUID, to name: String) throws {
        guard let program = try activeProgram() else { throw ProgramEditingError.noActiveProgram }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let w = program.workouts.first(where: { $0.id == id }) else {
            throw ProgramEditingError.workoutNotFound
        }
        w.name = trimmed
        try modelContext.save()
    }

    /// Updates an existing schedule row for this calendar day only (no cascade). Used where the full horizon shift is not desired.
    func setScheduleDay(date: CalendarDate, value: ProgramDaySchedulePickerValue) throws {
        guard let program = try activeProgram() else { return }
        guard let entry = program.scheduleEntries.first(where: {
            $0.year == date.year && $0.month == date.month && $0.day == date.day
        }) else { return }
        applySchedulePickerValue(value, to: entry, program: program)
        try modelContext.save()
    }

    /// Assigns `value` to `start`, then moves the assignment that **was** on `start` (and every later day through the forward horizon) one calendar day forward — the same cascade as **Add a rest day**, except the first day becomes `value` instead of rest.
    ///
    /// This keeps the relative order of later workouts/rest days after you realign one day (e.g. after a missed session).
    /// - Parameter skipIfUnchanged: When `true`, returns without saving if `start` already equals `value` (picker no-op). When `false`, always cascades (**Add a rest day** uses this so inserting rest still pushes the schedule even when that day was already rest).
    /// - Parameter preferNearestRecurrence: When `true` (the default) and `value` already recurs within the next
    ///   `nearDuplicateSearchWindow` days, rotates just that bounded window (`start` through the recurrence)
    ///   instead of shifting the entire remaining horizon — see doc comment inside the method. Pass `false` for
    ///   an unconditional insert (**Add a rest day** always wants to add a day, never swap to an existing one).
    func setScheduleDayShiftingFollowing(
        from start: CalendarDate,
        value: ProgramDaySchedulePickerValue,
        calendar: Calendar = .current,
        skipIfUnchanged: Bool = true,
        preferNearestRecurrence: Bool = true
    ) throws {
        try ensureForwardScheduleFilled(calendar: calendar)
        guard let program = try activeProgram() else { return }

        // One entry per calendar day (last wins if the store ever contained duplicates).
        var entryByDate: [CalendarDate: PersistedScheduleEntry] = [:]
        for entry in program.scheduleEntries {
            let cd = CalendarDate(year: entry.year, month: entry.month, day: entry.day)
            entryByDate[cd] = entry
        }

        let startOfToday = calendar.startOfDay(for: Date())
        guard let boundaryDate = calendar.date(byAdding: .day, value: Self.forwardScheduleHorizonDays - 1, to: startOfToday) else { return }
        let scheduleEnd = CalendarDate(from: boundaryDate, calendar: calendar)
        guard start <= scheduleEnd else { return }

        // Full consecutive run [start, scheduleEnd] — independent of which rows exist yet.
        var days: [CalendarDate] = []
        var scan: CalendarDate? = start
        while let d = scan, d <= scheduleEnd {
            days.append(d)
            scan = d.addingDays(1, calendar: calendar)
        }
        guard !days.isEmpty else { return }

        let previousAtStart: ProgramDaySchedulePickerValue = {
            if let e = entryByDate[start] { return schedulePickerValue(from: e) }
            return .rest
        }()
        if skipIfUnchanged, previousAtStart == value {
            return
        }

        // Insert missing calendar days as rest so the cascade covers the whole horizon (gaps used to truncate the chain).
        for d in days where entryByDate[d] == nil {
            let entry = PersistedScheduleEntry(
                year: d.year,
                month: d.month,
                day: d.day,
                isRestDay: true,
                workoutID: nil
            )
            entry.program = program
            program.scheduleEntries.append(entry)
            modelContext.insert(entry)
            entryByDate[d] = entry
        }

        let oldValues = days.map { schedulePickerValue(from: entryByDate[$0]!) }

        guard let startEntry = entryByDate[start] else { return }

        // If `value` already recurs soon (e.g. pulling a workout that's due again in a few days to today,
        // rather than genuinely inserting something new), rotate just that bounded window instead of shifting
        // — and spilling one extra day onto — the entire rest of the horizon. Otherwise that recurrence shows
        // up again a few days later as an apparent duplicate/out-of-order repeat, and every day after it runs
        // one calendar day later than the spreadsheet's actual cycle from then on — compounding with every
        // such edit. Bounded to a search window rather than the full ~196-day horizon so a coincidental match
        // far in the future (not really "the same upcoming cycle slot") still falls through to a plain insert.
        if preferNearestRecurrence, days.count > 1 {
            let searchLimit = min(Self.nearDuplicateSearchWindow, days.count - 1)
            if let k = (1 ... searchLimit).first(where: { oldValues[$0] == value }) {
                applySchedulePickerValue(value, to: startEntry, program: program)
                for i in 1 ... k {
                    guard let dest = entryByDate[days[i]] else { continue }
                    applySchedulePickerValue(oldValues[i - 1], to: dest, program: program)
                }
                try modelContext.save()
                return
            }
        }

        applySchedulePickerValue(value, to: startEntry, program: program)
        if days.count > 1 {
            for i in 1 ..< days.count {
                guard let dest = entryByDate[days[i]] else { continue }
                applySchedulePickerValue(oldValues[i - 1], to: dest, program: program)
            }
        }
        let spilled = oldValues[days.count - 1]
        guard let spillDate = days[days.count - 1].addingDays(1, calendar: calendar) else {
            try modelContext.save()
            return
        }
        if let existing = entryByDate[spillDate] {
            applySchedulePickerValue(spilled, to: existing, program: program)
        } else {
            let entry = PersistedScheduleEntry(
                year: spillDate.year,
                month: spillDate.month,
                day: spillDate.day,
                isRestDay: true,
                workoutID: nil
            )
            applySchedulePickerValue(spilled, to: entry, program: program)
            entry.program = program
            program.scheduleEntries.append(entry)
            modelContext.insert(entry)
        }
        try modelContext.save()
    }

    /// Makes `start` a rest day and shifts later assignments forward (see `setScheduleDayShiftingFollowing`). Always cascades, even when `start` is already rest. Always inserts a genuinely new rest day — never swaps to a rest day that's already coming up soon (`preferNearestRecurrence: false`), since "add a rest day" specifically means one more day off, not a rearrangement.
    func insertRestDayShiftingFollowing(from start: CalendarDate, calendar: Calendar = .current) throws {
        try setScheduleDayShiftingFollowing(from: start, value: .rest, calendar: calendar, skipIfUnchanged: false, preferNearestRecurrence: false)
    }

    private func schedulePickerValue(from entry: PersistedScheduleEntry) -> ProgramDaySchedulePickerValue {
        if entry.isRestDay { return .rest }
        if let id = entry.workoutID { return .workout(id) }
        return .rest
    }

    private func applySchedulePickerValue(_ value: ProgramDaySchedulePickerValue, to entry: PersistedScheduleEntry, program: PersistedProgram) {
        switch value {
        case .rest:
            entry.isRestDay = true
            entry.workoutID = nil
        case .workout(let id):
            guard program.workouts.contains(where: { $0.id == id }) else {
                entry.isRestDay = true
                entry.workoutID = nil
                return
            }
            entry.isRestDay = false
            entry.workoutID = id
        }
    }

    @discardableResult
    func addWorkout(name: String = "New workout") throws -> PersistedWorkout {
        guard let program = try activeProgram() else {
            throw ProgramEditingError.noActiveProgram
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let order = (program.workouts.map(\.sortOrder).max() ?? -1) + 1
        let w = PersistedWorkout(name: trimmed.isEmpty ? "New workout" : trimmed, sortOrder: order)
        w.program = program
        program.workouts.append(w)
        modelContext.insert(w)
        let ex = PersistedExercise(name: "Exercise 1", sortOrder: 0, setCount: Self.defaultTemplateSetCount)
        ex.workout = w
        w.exercises.append(ex)
        modelContext.insert(ex)
        try modelContext.save()
        return w
    }

    func deleteWorkout(id: UUID) throws {
        guard let program = try activeProgram() else { return }
        guard let w = program.workouts.first(where: { $0.id == id }) else { return }
        for entry in program.scheduleEntries where entry.workoutID == id {
            entry.isRestDay = true
            entry.workoutID = nil
        }
        modelContext.delete(w)
        try modelContext.save()
    }

    func addExercise(toWorkout workoutId: UUID, name: String = "New exercise", setCount: Int = 4) throws {
        guard let program = try activeProgram(),
              let workout = program.workouts.first(where: { $0.id == workoutId })
        else { return }
        let order = (workout.exercises.map(\.sortOrder).max() ?? -1) + 1
        let count = max(1, min(20, setCount))
        let ex = PersistedExercise(name: name, sortOrder: order, setCount: count)
        ex.workout = workout
        workout.exercises.append(ex)
        modelContext.insert(ex)
        try modelContext.save()
    }

    /// Looks up a template exercise by id, throwing `.exerciseNotFound` instead of the silent no-ops the setters below used to do.
    private func requireExercise(id: UUID) throws -> PersistedExercise {
        guard let ex = try modelContext.first(PersistedExercise.self, matching: #Predicate<PersistedExercise> { $0.id == id }) else {
            throw ProgramEditingError.exerciseNotFound
        }
        return ex
    }

    func deleteExercise(id: UUID) throws {
        let ex = try requireExercise(id: id)
        guard let workout = ex.workout else {
            modelContext.delete(ex)
            try modelContext.save()
            return
        }
        modelContext.delete(ex)
        let remaining = workout.exercises.sorted { $0.sortOrder < $1.sortOrder }
        for (idx, e) in remaining.enumerated() {
            e.sortOrder = idx
        }
        try modelContext.save()
    }

    func setExerciseName(id: UUID, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ex = try requireExercise(id: id)
        ex.name = trimmed
        try modelContext.save()
    }

    func setExerciseSetCount(id: UUID, setCount: Int) throws {
        let ex = try requireExercise(id: id)
        ex.setCount = max(1, min(20, setCount))
        try modelContext.save()
    }

    func setExerciseRepsPerSide(id: UUID, value: Bool) throws {
        let ex = try requireExercise(id: id)
        ex.repsArePerSide = value
        try modelContext.save()
    }

    /// Switching to cardio resets the set count to **1** — a cardio exercise is normally a single set (one
    /// duration/heart-rate reading), not a strength-style multi-set default. Still adjustable afterward via the
    /// usual "Sets to log" stepper for anyone who wants more (e.g. interval rounds).
    func setExerciseKind(id: UUID, kind: ExerciseKind) throws {
        let ex = try requireExercise(id: id)
        ex.kind = kind
        if kind == .cardio {
            ex.setCount = 1
        }
        try modelContext.save()
    }

    /// Trims and nils out empty text — parity with `setExerciseName`. Used by both the Program tab and the workout logger so note-saving isn’t duplicated per screen.
    func setExerciseNote(id: UUID, note: String?) throws {
        let ex = try requireExercise(id: id)
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        ex.note = (trimmed?.isEmpty ?? true) ? nil : trimmed
        try modelContext.save()
    }

    func reorderExercises(inWorkout workoutId: UUID, orderedExerciseIds: [UUID]) throws {
        guard let program = try activeProgram(),
              let workout = program.workouts.first(where: { $0.id == workoutId })
        else { return }
        let idSet = Set(workout.exercises.map(\.id))
        guard Set(orderedExerciseIds) == idSet else { return }
        for (idx, eid) in orderedExerciseIds.enumerated() {
            guard let ex = workout.exercises.first(where: { $0.id == eid }) else { continue }
            ex.sortOrder = idx
        }
        try modelContext.save()
    }
}

enum ProgramEditingError: Error {
    case noActiveProgram
    case programAlreadyExists
    case workoutNotFound
    case exerciseNotFound
}

extension ProgramEditingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noActiveProgram:
            "No active program."
        case .programAlreadyExists:
            "A program is already set up. Use Settings → Import to replace it with a spreadsheet."
        case .workoutNotFound:
            "That workout no longer exists."
        case .exerciseNotFound:
            "That exercise no longer exists."
        }
    }
}

//
//  Set_BuddyTests.swift
//  Set BuddyTests
//
//  Created by PETE MOUNTANOS on 3/22/26.
//

import Foundation
import SwiftData
import Testing
@testable import Set_Buddy

private final class ImportTestBundleToken {}
private final class SetBuddy2FixtureToken {}
private final class SetBuddy4FixtureToken {}

private struct StubDateProvider: DateProviding {
    let now: Date
}

/// `.serialized`: many tests here create their own in-memory `ModelContainer`. Swift Testing runs tests concurrently
/// by default, and SwiftData's underlying persistent-store machinery isn't safe under that many containers being
/// spun up in true parallel — it crashes with SIGTRAP under load (reproduced: 31/35 tests crashed when run unserialized,
/// all in `ModelContext.fetch`). Running the suite's tests one at a time avoids the race.
@Suite(.serialized)
@MainActor
struct Set_BuddyTests {
    /// Fresh in-memory `ModelContainer`/`ModelContext` pair with the full schema — avoids repeating the same
    /// `Schema`/`ModelConfiguration`/`ModelContainer` boilerplate in every persistence test.
    ///
    /// Returns the container alongside its context (not just the context): an in-memory `ModelContainer`'s store is
    /// torn down when the container deallocates, and `container.mainContext` does not keep it alive on its own —
    /// callers must hold the returned tuple for as long as they use `.context`, or fetches crash.
    private static func makeInMemoryStore() throws -> (container: ModelContainer, context: ModelContext) {
        let schema = Schema([
            PersistedProgram.self,
            PersistedWorkout.self,
            PersistedScheduleEntry.self,
            PersistedExercise.self,
            PersistedWorkoutSession.self,
            PersistedLoggedSet.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return (container, container.mainContext)
    }

    @Test func calendarDateOrdersLexicographically() {
        let a = CalendarDate(year: 2026, month: 3, day: 21)
        let b = CalendarDate(year: 2026, month: 3, day: 22)
        #expect(a < b)
        #expect(b > a)
    }

    @Test func programCalendarScheduleLookup() {
        let id = UUID()
        let d = CalendarDate(year: 2026, month: 1, day: 15)
        var schedule = ProgramCalendarSchedule()
        schedule.set(.workout(workoutId: id), on: d)
        #expect(schedule.scheduledKind(on: d) == .workout(workoutId: id))
        #expect(schedule.scheduledKind(on: CalendarDate(year: 2026, month: 1, day: 16)) == nil)
    }

    @Test func calendarDateFromDateUsesCalendar() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_737_158_400) // 2025-01-18 00:00:00 UTC
        let cd = CalendarDate(from: date, calendar: cal)
        #expect(cd.year == 2025 && cd.month == 1 && cd.day == 18)
    }

    @Test func parsesBundledSetBuddyXlsx() throws {
        let bundle = Bundle(for: ImportTestBundleToken.self)
        guard let url = bundle.url(forResource: "Set Buddy", withExtension: "xlsx") else {
            Issue.record("Expected Set Buddy.xlsx in the test bundle (copy from your Downloads if missing).")
            return
        }
        let data = try Data(contentsOf: url)
        let cycle = try ProgramXlsxParser.parse(xlsxData: data)
        #expect(cycle.count == 8)
        #expect(cycle.first?.sheetName == "Push 1")
        let push1 = cycle.first { $0.sheetName == "Push 1" }
        #expect(push1?.isRestDay == false)
        #expect((push1?.exercises.count ?? 0) >= 5)
        let rest1 = cycle.first { $0.sheetName == "Rest 1" }
        #expect(rest1?.isRestDay == true)
    }

    @Test func volumeCalculatorTotalsSets() {
        let parts: [(Double, Int)] = [(100, 5), (50, 10)]
        let total = VolumeCalculator.totalVolume(sets: parts.map { (weight: $0.0, reps: $0.1, repsArePerSide: false) })
        #expect(total == 100 * 5 + 50 * 10)
    }

    @Test func todayScheduleResolverDayNotScheduledWhenEmpty() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let noon = Date(timeIntervalSince1970: 1_737_158_400).addingTimeInterval(43_200)
        let schedule = ProgramCalendarSchedule()
        let s = TodayScheduleResolver.status(
            now: noon,
            calendar: cal,
            schedule: schedule,
            workoutNames: [:]
        )
        #expect(s == .dayNotScheduled)
    }

    @Test func todayScheduleResolverWorkoutAndRest() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let wid = UUID()
        let noon = Date(timeIntervalSince1970: 1_737_158_400).addingTimeInterval(43_200) // 2025-01-18 12:00 UTC
        var schedule = ProgramCalendarSchedule()
        schedule.set(.workout(workoutId: wid), on: CalendarDate(from: noon, calendar: cal))
        let s1 = TodayScheduleResolver.status(
            now: noon,
            calendar: cal,
            schedule: schedule,
            workoutNames: [wid: "Push"]
        )
        #expect(s1 == .workoutDay(workoutId: wid, title: "Push"))

        schedule.set(.rest, on: CalendarDate(from: noon, calendar: cal))
        let s2 = TodayScheduleResolver.status(now: noon, calendar: cal, schedule: schedule, workoutNames: [:])
        #expect(s2 == .restDay)
    }

    @Test func volumeSetTreatsNegativeWeightAsZero() {
        #expect(VolumeCalculator.setVolume(weight: -50, reps: 10) == 0)
    }

    @Test func volumeSetZeroReps() {
        #expect(VolumeCalculator.setVolume(weight: 200, reps: 0) == 0)
    }

    @Test func volumeSetPerSideDoublesWork() {
        #expect(VolumeCalculator.setVolume(weight: 50, reps: 10, repsArePerSide: false) == 500)
        #expect(VolumeCalculator.setVolume(weight: 50, reps: 10, repsArePerSide: true) == 1_000)
    }

    @Test func importDetectsPerSideInColumnBWhenHeadersSayPerSideNotes() {
        // Mirrors `Set Buddy-2.xlsx`: A=name, B=per side, C=notes (not B=note, C=per side).
        let cells: [String: String] = [
            "A1": "Excercise_Name", "B1": "Per side", "C1": "Notes",
            "A2": "Plate-Loaded Incline Chest Press", "B2": "x",
            "A3": "Converging Chest Press Machine",
            "A4": "Pec Deck", "C4": "chest fly machine acceptable",
        ]
        let exercises = ProgramXlsxParser.exercisesFromCells(cells)
        #expect(exercises.count == 3)
        #expect(exercises[0].name == "Plate-Loaded Incline Chest Press")
        #expect(exercises[0].repsArePerSide == true)
        #expect(exercises[0].note == nil)
        #expect(exercises[1].name == "Converging Chest Press Machine")
        #expect(exercises[1].repsArePerSide == false)
        #expect(exercises[2].note == "chest fly machine acceptable")
        #expect(exercises[2].repsArePerSide == false)
    }

    /// Regression: real workbook `Fixtures/Set Buddy-2.xlsx` uses B = per-side, C = notes.
    @Test func parsesSetBuddy2Fixture_perSideAndNotesColumns() throws {
        let bundle = Bundle(for: SetBuddy2FixtureToken.self)
        guard let url = bundle.url(forResource: "Set Buddy-2", withExtension: "xlsx") else {
            Issue.record("Add Fixtures/Set Buddy-2.xlsx to the Set BuddyTests folder (synced into the test bundle).")
            return
        }
        let data = try Data(contentsOf: url)
        let cycle = try ProgramXlsxParser.parse(xlsxData: data)
        let push1 = try #require(cycle.first { $0.sheetName == "Push 1" })
        #expect(push1.isRestDay == false)
        let byName = Dictionary(uniqueKeysWithValues: push1.exercises.map { ($0.name, $0) })

        let plate = try #require(byName["Plate-Loaded Incline Chest Press"])
        #expect(plate.repsArePerSide == true)
        #expect(plate.note == nil)

        let converging = try #require(byName["Converging Chest Press Machine"])
        #expect(converging.repsArePerSide == true)

        let pec = try #require(byName["Pec Deck"])
        #expect(pec.repsArePerSide == false)
        #expect(pec.note?.contains("chest fly") == true)

        let incline = try #require(byName["Incline Dumbell Shoulder Press"])
        #expect(incline.repsArePerSide == true)
    }

    @Test @MainActor func importsSetBuddy2Fixture_repsPerSideOnPersistedTemplates() throws {
        let bundle = Bundle(for: SetBuddy2FixtureToken.self)
        guard let url = bundle.url(forResource: "Set Buddy-2", withExtension: "xlsx") else {
            Issue.record("Missing Fixtures/Set Buddy-2.xlsx in test bundle.")
            return
        }
        let data = try Data(contentsOf: url)
        let schema = Schema([
            PersistedProgram.self,
            PersistedWorkout.self,
            PersistedScheduleEntry.self,
            PersistedExercise.self,
            PersistedWorkoutSession.self,
            PersistedLoggedSet.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        try ProgramXlsxImporter.importReplacingStore(
            xlsx: data,
            programName: "Fixture Import",
            startDate: CalendarDate(year: 2026, month: 3, day: 24),
            modelContext: context,
            horizonDays: 16,
            cycleStartIndex: 0
        )

        let workouts = try context.fetch(FetchDescriptor<PersistedWorkout>())
        let push1 = try #require(workouts.first { $0.name == "Push 1" })
        let plate = try #require(push1.exercises.first { $0.name == "Plate-Loaded Incline Chest Press" })
        #expect(plate.repsArePerSide == true)
        let pec = try #require(push1.exercises.first { $0.name == "Pec Deck" })
        #expect(pec.repsArePerSide == false)
        #expect(pec.note?.contains("chest fly") == true)
    }

    @Test func spreadsheetPerSideColumnAcceptsExcelStyleMarkers() {
        #expect(ProgramXlsxParser.spreadsheetMarksRepsPerSide("x"))
        #expect(ProgramXlsxParser.spreadsheetMarksRepsPerSide("X"))
        #expect(ProgramXlsxParser.spreadsheetMarksRepsPerSide("×"))
        #expect(ProgramXlsxParser.spreadsheetMarksRepsPerSide("TRUE"))
        #expect(ProgramXlsxParser.spreadsheetMarksRepsPerSide("true"))
        #expect(ProgramXlsxParser.spreadsheetMarksRepsPerSide("1"))
        #expect(ProgramXlsxParser.spreadsheetMarksRepsPerSide("yes"))
        #expect(ProgramXlsxParser.spreadsheetMarksRepsPerSide("Y"))
        #expect(ProgramXlsxParser.spreadsheetMarksRepsPerSide("✓"))
        #expect(!ProgramXlsxParser.spreadsheetMarksRepsPerSide(nil))
        #expect(!ProgramXlsxParser.spreadsheetMarksRepsPerSide(""))
        #expect(!ProgramXlsxParser.spreadsheetMarksRepsPerSide("0"))
        #expect(!ProgramXlsxParser.spreadsheetMarksRepsPerSide("no"))
    }

    @Test func workoutTemplateDisplaySortOrdersPushPullLegsCycle() {
        let names = ["Legs 2", "Push 1", "Pull 2", "Pull 1", "Push 2", "Legs 1", "ZZ Other"]
        let sorted = names.sorted { WorkoutTemplateDisplaySort.compare($0, $1) }
        #expect(
            sorted == ["Push 1", "Pull 1", "Legs 1", "Push 2", "Pull 2", "Legs 2", "ZZ Other"]
        )
    }

    @Test func parseEmptyXlsxDataThrowsInvalidArchive() {
        #expect(throws: ProgramImportError.invalidXlsxArchive) {
            _ = try ProgramXlsxParser.parse(xlsxData: Data())
        }
    }

    @Test @MainActor func createFirstProgramBuildsStarterWorkoutAndRestSchedule() throws {
        let schema = Schema([
            PersistedProgram.self,
            PersistedWorkout.self,
            PersistedScheduleEntry.self,
            PersistedExercise.self,
            PersistedWorkoutSession.self,
            PersistedLoggedSet.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let program = try ProgramRepository(modelContext: context).createFirstProgram(name: "  Built here  ")
        #expect(program.name == "Built here")
        #expect(program.workouts.count == 1)
        #expect(program.workouts.first?.name == "Workout 1")
        #expect(program.workouts.first?.exercises.count == 1)
        #expect(program.scheduleEntries.count == ProgramRepository.forwardScheduleHorizonDays)

        let calendar = Calendar.current
        let rows = try ProgramOutlineRepository(modelContext: context).upcomingScheduleRows(limit: 3, calendar: calendar)
        #expect(rows.count == 3)
        #expect(rows.filter { !$0.isRestDay }.isEmpty)

        #expect(throws: ProgramEditingError.programAlreadyExists) {
            try ProgramRepository(modelContext: context).createFirstProgram(name: "Nope")
        }
    }

    @Test @MainActor func startOverFreshProgramReplacesWithNewStarter() throws {
        let schema = Schema([
            PersistedProgram.self,
            PersistedWorkout.self,
            PersistedScheduleEntry.self,
            PersistedExercise.self,
            PersistedWorkoutSession.self,
            PersistedLoggedSet.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let repo = ProgramRepository(modelContext: context)
        _ = try repo.createFirstProgram(name: "Before")
        #expect(try repo.activeProgram()?.name == "Before")

        _ = try repo.startOverFreshProgram(name: "After")
        #expect(try repo.activeProgram()?.name == "After")

        let outline = try ProgramOutlineRepository(modelContext: context).activeProgramOutline()
        #expect(outline?.workouts.count == 1)
        #expect(outline?.workouts.first?.name == "Workout 1")
    }

    @Test func notificationSettingsRoundTripInSuite() {
        let suiteName = "test.SetBuddy.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create UserDefaults suite.")
            return
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let original = NotificationSettings(dailyRemindersEnabled: false, hour: 14, minute: 45)
        original.save(to: suite)
        let loaded = NotificationSettings.load(from: suite)
        #expect(loaded == original)
    }

    @Test @MainActor func upcomingScheduleRowsRespectsTodayAndLimit() throws {
        let schema = Schema([
            PersistedProgram.self,
            PersistedWorkout.self,
            PersistedScheduleEntry.self,
            PersistedExercise.self,
            PersistedWorkoutSession.self,
            PersistedLoggedSet.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())

        let program = PersistedProgram(name: "Test Program")
        let workout = PersistedWorkout(name: "Day A")
        workout.program = program
        program.workouts.append(workout)

        for offset in 0 ..< 6 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let cd = CalendarDate(from: date, calendar: calendar)
            let isRest = offset == 3
            let entry = PersistedScheduleEntry(
                year: cd.year,
                month: cd.month,
                day: cd.day,
                isRestDay: isRest,
                workoutID: isRest ? nil : workout.id
            )
            entry.program = program
            program.scheduleEntries.append(entry)
        }

        context.insert(program)
        try context.save()

        let rows = try ProgramOutlineRepository(modelContext: context).upcomingScheduleRows(limit: 14, calendar: calendar)
        #expect(rows.count == 6)
        #expect(rows.contains { $0.isRestDay && $0.subtitle == "Rest" })
        #expect(rows.filter { !$0.isRestDay }.count == 5)

        let limited = try ProgramOutlineRepository(modelContext: context).upcomingScheduleRows(limit: 3, calendar: calendar)
        #expect(limited.count == 3)
    }

    @Test @MainActor func insertRestDayShiftsFollowingScheduleDays() throws {
        let schema = Schema([
            PersistedProgram.self,
            PersistedWorkout.self,
            PersistedScheduleEntry.self,
            PersistedExercise.self,
            PersistedWorkoutSession.self,
            PersistedLoggedSet.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())

        let program = PersistedProgram(name: "Shift Test")
        let wA = PersistedWorkout(name: "Workout A")
        let wB = PersistedWorkout(name: "Workout B")
        wA.program = program
        wB.program = program
        program.workouts.append(contentsOf: [wA, wB])

        for offset in 0 ..< 4 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let cd = CalendarDate(from: date, calendar: calendar)
            let workoutID: UUID?
            let isRest: Bool
            switch offset {
            case 0: workoutID = wA.id; isRest = false
            case 1: workoutID = wB.id; isRest = false
            case 2: workoutID = wA.id; isRest = false
            default: workoutID = nil; isRest = true
            }
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

        context.insert(program)
        try context.save()

        let day0 = CalendarDate(from: start, calendar: calendar)
        try ProgramRepository(modelContext: context).insertRestDayShiftingFollowing(from: day0, calendar: calendar)

        func entry(on date: Date) -> PersistedScheduleEntry? {
            let cd = CalendarDate(from: date, calendar: calendar)
            return program.scheduleEntries.first {
                $0.year == cd.year && $0.month == cd.month && $0.day == cd.day
            }
        }

        guard let d0 = entry(on: start),
              let d1 = entry(on: calendar.date(byAdding: .day, value: 1, to: start)!),
              let d2 = entry(on: calendar.date(byAdding: .day, value: 2, to: start)!),
              let d3 = entry(on: calendar.date(byAdding: .day, value: 3, to: start)!),
              let d4 = entry(on: calendar.date(byAdding: .day, value: 4, to: start)!)
        else {
            Issue.record("Expected schedule entries for five consecutive days.")
            return
        }

        #expect(d0.isRestDay && d0.workoutID == nil)
        #expect(!d1.isRestDay && d1.workoutID == wA.id)
        #expect(!d2.isRestDay && d2.workoutID == wB.id)
        #expect(!d3.isRestDay && d3.workoutID == wA.id)
        #expect(d4.isRestDay && d4.workoutID == nil)
    }

    /// Changing a day via the schedule menu should cascade like insert-rest so later days keep the prior order.
    @Test @MainActor func setSchedulePickerShiftMovesLaterAssignmentsForward() throws {
        let schema = Schema([
            PersistedProgram.self,
            PersistedWorkout.self,
            PersistedScheduleEntry.self,
            PersistedExercise.self,
            PersistedWorkoutSession.self,
            PersistedLoggedSet.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())

        let program = PersistedProgram(name: "Cascade Test")
        let wA = PersistedWorkout(name: "Workout A")
        let wB = PersistedWorkout(name: "Workout B")
        wA.program = program
        wB.program = program
        program.workouts.append(contentsOf: [wA, wB])

        for offset in 0 ..< 4 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let cd = CalendarDate(from: date, calendar: calendar)
            let workoutID: UUID?
            let isRest: Bool
            switch offset {
            case 0: workoutID = wA.id; isRest = false
            case 1: workoutID = wB.id; isRest = false
            case 2: workoutID = wA.id; isRest = false
            default: workoutID = nil; isRest = true
            }
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

        context.insert(program)
        try context.save()

        let day1Date = calendar.date(byAdding: .day, value: 1, to: start)!
        let day1 = CalendarDate(from: day1Date, calendar: calendar)

        try ProgramRepository(modelContext: context).setScheduleDayShiftingFollowing(
            from: day1,
            value: .workout(wA.id),
            calendar: calendar
        )

        func entry(on date: Date) -> PersistedScheduleEntry? {
            let cd = CalendarDate(from: date, calendar: calendar)
            return program.scheduleEntries.first {
                $0.year == cd.year && $0.month == cd.month && $0.day == cd.day
            }
        }

        guard let d0 = entry(on: start),
              let d1 = entry(on: day1Date),
              let d2 = entry(on: calendar.date(byAdding: .day, value: 2, to: start)!),
              let d3 = entry(on: calendar.date(byAdding: .day, value: 3, to: start)!),
              let d4 = entry(on: calendar.date(byAdding: .day, value: 4, to: start)!)
        else {
            Issue.record("Expected schedule entries for five consecutive days.")
            return
        }

        // A was already due again the day after day1 (day2, old value), so this swaps day1 <-> day2
        // (day1: B -> A, day2: A -> B) rather than shifting the whole horizon: day3 (rest) is untouched.
        #expect(!d0.isRestDay && d0.workoutID == wA.id)
        #expect(!d1.isRestDay && d1.workoutID == wA.id)
        #expect(!d2.isRestDay && d2.workoutID == wB.id)
        #expect(d3.isRestDay && d3.workoutID == nil)
        #expect(d4.isRestDay && d4.workoutID == nil)
    }

    /// Regression for a real report: importing a multi-day named cycle (Push/Cardio/Pull/Cardio/Legs/Rest, e.g.)
    /// and then forcing one day onto a workout that's due again a few days later used to insert a duplicate of
    /// that workout and permanently delay every later day by one -- "days get out of order" relative to the
    /// spreadsheet. This mirrors that shape with a recurrence 3 days out, not just 1, to prove the bounded
    /// window correctly threads through several intermediate days rather than only handling the adjacent case.
    @Test @MainActor func setScheduleDayShiftingFollowingSwapsDistantRecurrenceWithoutDelayingLaterDays() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())

        let program = PersistedProgram(name: "Cycle Test")
        let push = PersistedWorkout(name: "Push")
        let pull = PersistedWorkout(name: "Pull")
        let legs = PersistedWorkout(name: "Legs")
        push.program = program
        pull.program = program
        legs.program = program
        program.workouts.append(contentsOf: [push, pull, legs])

        // day0 = Push, day1 = Pull, day2 = Rest, day3 = Legs, day4 = Rest, day5 = Push (next cycle), ...
        let cycle: [(UUID?, Bool)] = [
            (push.id, false), (pull.id, false), (nil, true), (legs.id, false), (nil, true), (push.id, false),
        ]
        for (offset, slot) in cycle.enumerated() {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let cd = CalendarDate(from: date, calendar: calendar)
            let entry = PersistedScheduleEntry(year: cd.year, month: cd.month, day: cd.day, isRestDay: slot.1, workoutID: slot.0)
            entry.program = program
            program.scheduleEntries.append(entry)
        }
        context.insert(program)
        try context.save()

        // Force day0 (was Push) onto Legs, which was already due on day3.
        try ProgramRepository(modelContext: context).setScheduleDayShiftingFollowing(
            from: CalendarDate(from: start, calendar: calendar),
            value: .workout(legs.id),
            calendar: calendar
        )

        func entry(daysFromStart offset: Int) -> PersistedScheduleEntry? {
            let cd = CalendarDate(from: calendar.date(byAdding: .day, value: offset, to: start)!, calendar: calendar)
            return program.scheduleEntries.first { $0.year == cd.year && $0.month == cd.month && $0.day == cd.day }
        }
        // Legs pulled forward to day0; Push/Pull/Rest (days0-2's old values) shift into days1-3; day4 onward —
        // Rest, then the next cycle's Push — are completely untouched, not delayed by a day.
        #expect(entry(daysFromStart: 0)?.workoutID == legs.id)
        #expect(entry(daysFromStart: 1)?.workoutID == push.id)
        #expect(entry(daysFromStart: 2)?.workoutID == pull.id)
        #expect(entry(daysFromStart: 3)?.isRestDay == true)
        #expect(entry(daysFromStart: 4)?.isRestDay == true)
        #expect(entry(daysFromStart: 5)?.workoutID == push.id)
    }

    @Test @MainActor func historySessionDetailAggregatesVolume() throws {
        let schema = Schema([
            PersistedProgram.self,
            PersistedWorkout.self,
            PersistedScheduleEntry.self,
            PersistedExercise.self,
            PersistedWorkoutSession.self,
            PersistedLoggedSet.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let program = PersistedProgram(name: "P")
        let workout = PersistedWorkout(name: "Legs")
        workout.program = program
        program.workouts.append(workout)

        let exercise = PersistedExercise(name: "Squat", sortOrder: 0, setCount: 2)
        exercise.workout = workout
        workout.exercises.append(exercise)

        let cal = Calendar.current
        let cd = CalendarDate(from: Date(), calendar: cal)
        let session = PersistedWorkoutSession(
            workoutTemplateId: workout.id,
            scheduleYear: cd.year,
            scheduleMonth: cd.month,
            scheduleDay: cd.day
        )
        session.isComplete = true
        session.completedAt = Date()
        session.workoutTitleSnapshot = "Legs"

        let set0 = PersistedLoggedSet(exerciseId: exercise.id, setIndex: 0, weight: 100, reps: 5)
        let set1 = PersistedLoggedSet(exerciseId: exercise.id, setIndex: 1, weight: 100, reps: 5)
        set0.session = session
        set1.session = session
        session.loggedSets.append(contentsOf: [set0, set1])

        context.insert(program)
        context.insert(session)
        try context.save()

        let detail = try HistoryRepository(modelContext: context).sessionDetail(sessionId: session.id)
        #expect(detail != nil)
        #expect(detail?.workoutTitle == "Legs")
        #expect(detail?.exercises.count == 1)
        #expect(detail?.exercises.first?.name == "Squat")
        #expect(detail?.exercises.first?.sets.count == 2)
        #expect(detail?.totalVolume == 1_000)
    }

    // MARK: - WorkoutSessionRepository sync

    @Test func getOrCreateActiveSessionAddsRowsWhenTemplateGainsSets() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let program = PersistedProgram(name: "P")
        let workout = PersistedWorkout(name: "Day A")
        workout.program = program
        program.workouts.append(workout)
        let exercise = PersistedExercise(name: "Squat", sortOrder: 0, setCount: 2)
        exercise.workout = workout
        workout.exercises.append(exercise)
        context.insert(program)
        try context.save()

        let day = CalendarDate(from: Date(), calendar: .current)
        let repo = WorkoutSessionRepository(modelContext: context)
        let session = try repo.getOrCreateActiveSession(templateId: workout.id, day: day, workout: workout)
        #expect(session.loggedSets.count == 2)

        // Template gains a third set while the session is in progress.
        exercise.setCount = 3
        try context.save()
        let resynced = try repo.getOrCreateActiveSession(templateId: workout.id, day: day, workout: workout)
        #expect(resynced.loggedSets.count == 3)
        #expect(resynced.id == session.id)
    }

    @Test func getOrCreateActiveSessionPrunesRowsWhenTemplateLosesSets() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let program = PersistedProgram(name: "P")
        let workout = PersistedWorkout(name: "Day A")
        workout.program = program
        program.workouts.append(workout)
        let exercise = PersistedExercise(name: "Squat", sortOrder: 0, setCount: 4)
        exercise.workout = workout
        workout.exercises.append(exercise)
        context.insert(program)
        try context.save()

        let day = CalendarDate(from: Date(), calendar: .current)
        let repo = WorkoutSessionRepository(modelContext: context)
        _ = try repo.getOrCreateActiveSession(templateId: workout.id, day: day, workout: workout)

        exercise.setCount = 2
        try context.save()
        let resynced = try repo.getOrCreateActiveSession(templateId: workout.id, day: day, workout: workout)
        #expect(resynced.loggedSets.count == 2)
        #expect(resynced.loggedSets.allSatisfy { $0.setIndex < 2 })
    }

    @Test func getOrCreateActiveSessionSyncsPerSideFlagFromTemplate() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let program = PersistedProgram(name: "P")
        let workout = PersistedWorkout(name: "Day A")
        workout.program = program
        program.workouts.append(workout)
        let exercise = PersistedExercise(name: "Curl", sortOrder: 0, setCount: 1, repsArePerSide: false)
        exercise.workout = workout
        workout.exercises.append(exercise)
        context.insert(program)
        try context.save()

        let day = CalendarDate(from: Date(), calendar: .current)
        let repo = WorkoutSessionRepository(modelContext: context)
        let session = try repo.getOrCreateActiveSession(templateId: workout.id, day: day, workout: workout)
        #expect(session.loggedSets.first?.repsArePerSide == false)

        exercise.repsArePerSide = true
        try context.save()
        let resynced = try repo.getOrCreateActiveSession(templateId: workout.id, day: day, workout: workout)
        #expect(resynced.loggedSets.first?.repsArePerSide == true)
    }

    @Test func updateLoggedSetMarksUserEnteredAndClampsNegativeValues() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let program = PersistedProgram(name: "P")
        let workout = PersistedWorkout(name: "Day A")
        workout.program = program
        program.workouts.append(workout)
        let exercise = PersistedExercise(name: "Bench", sortOrder: 0, setCount: 1)
        exercise.workout = workout
        workout.exercises.append(exercise)
        context.insert(program)
        try context.save()

        let day = CalendarDate(from: Date(), calendar: .current)
        let repo = WorkoutSessionRepository(modelContext: context)
        let session = try repo.getOrCreateActiveSession(templateId: workout.id, day: day, workout: workout)

        try repo.updateLoggedSet(session: session, exerciseId: exercise.id, setIndex: 0, weight: -10, reps: -5)
        let row = try #require(session.loggedSets.first)
        #expect(row.weight == 0)
        #expect(row.reps == 0)
        #expect(row.userEditedValues == true)
    }

    @Test func completeSessionDropsUnenteredRowsAndSnapshotsTitle() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let program = PersistedProgram(name: "P")
        let workout = PersistedWorkout(name: "Day A")
        workout.program = program
        program.workouts.append(workout)
        let exercise = PersistedExercise(name: "Bench", sortOrder: 0, setCount: 2)
        exercise.workout = workout
        workout.exercises.append(exercise)
        context.insert(program)
        try context.save()

        let day = CalendarDate(from: Date(), calendar: .current)
        let repo = WorkoutSessionRepository(modelContext: context)
        let session = try repo.getOrCreateActiveSession(templateId: workout.id, day: day, workout: workout)
        try repo.updateLoggedSet(session: session, exerciseId: exercise.id, setIndex: 0, weight: 100, reps: 5)

        try repo.completeSession(session, workoutTitle: "Day A")
        #expect(session.isComplete == true)
        #expect(session.workoutTitleSnapshot == "Day A")
        #expect(session.loggedSets.count == 1)
        #expect(session.loggedSets.first?.setIndex == 0)
    }

    // MARK: - ProgramRepository exercise editing

    @Test func setExerciseNoteTrimsAndNilsEmptyText() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let program = PersistedProgram(name: "P")
        let workout = PersistedWorkout(name: "Day A")
        workout.program = program
        program.workouts.append(workout)
        let exercise = PersistedExercise(name: "Bench", sortOrder: 0, setCount: 1)
        exercise.workout = workout
        workout.exercises.append(exercise)
        context.insert(program)
        try context.save()

        let repo = ProgramRepository(modelContext: context)
        try repo.setExerciseNote(id: exercise.id, note: "  Elbows tucked  ")
        #expect(exercise.note == "Elbows tucked")

        try repo.setExerciseNote(id: exercise.id, note: "   ")
        #expect(exercise.note == nil)
    }

    @Test func setExerciseNameThrowsExerciseNotFoundForUnknownId() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let repo = ProgramRepository(modelContext: context)
        #expect(throws: ProgramEditingError.exerciseNotFound) {
            try repo.setExerciseName(id: UUID(), name: "Anything")
        }
    }

    // MARK: - WorkoutTemplateEditorViewModel

    @Test func workoutTemplateEditorAddsDeletesAndReordersExercises() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let repo = ProgramRepository(modelContext: context)
        let program = try repo.createFirstProgram(name: "Test")
        let workout = try #require(program.workouts.first)
        let outline = try #require(try ProgramOutlineRepository(modelContext: context).activeProgramOutline())
        let workoutOutline = try #require(outline.workouts.first { $0.id == workout.id })

        let editor = WorkoutTemplateEditorViewModel(modelContext: context)
        editor.present(workout: workoutOutline)
        #expect(editor.rows.count == 1)

        editor.addExercise()
        #expect(editor.rows.count == 2)

        editor.workoutName = "Renamed workout"
        editor.persistTitleAndReset()
        #expect(try repo.activeProgram()?.workouts.first?.name == "Renamed workout")
        #expect(editor.workoutId == nil)
        #expect(editor.rows.isEmpty)
    }

    // MARK: - Spreadsheet export

    @Test func spreadsheetFormattingCsvEscapeQuotesSpecialCharacters() {
        #expect(SpreadsheetFormatting.csvEscape("Plain") == "Plain")
        #expect(SpreadsheetFormatting.csvEscape("a,b") == "\"a,b\"")
        #expect(SpreadsheetFormatting.csvEscape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(SpreadsheetFormatting.csvEscape("line1\nline2") == "\"line1\nline2\"")
    }

    @Test func spreadsheetFormattingCsvDataStartsWithUtf8Bom() {
        let data = SpreadsheetFormatting.csvData(lines: ["a,b", "1,2"])
        #expect(data.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        let text = String(data: data.dropFirst(3), encoding: .utf8)
        #expect(text == "a,b\n1,2")
    }

    @Test @MainActor func programSpreadsheetExportXlsxRoundTripsThroughArchiveReader() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let repo = ProgramRepository(modelContext: context)
        let program = try repo.createFirstProgram(name: "Round Trip")

        let data = try ProgramSpreadsheetExport.buildXlsx(program: program)
        let workbookXml = try XlsxArchiveReader.extract("xl/workbook.xml", fromXlsx: data)
        let workbookText = try #require(String(data: workbookXml, encoding: .utf8))
        #expect(workbookText.contains("Workout 1"))

        let sheetXml = try XlsxArchiveReader.extract("xl/worksheets/sheet1.xml", fromXlsx: data)
        let sheetText = try #require(String(data: sheetXml, encoding: .utf8))
        #expect(sheetText.contains("Exercise 1"))
    }

    @Test func programSpreadsheetExportCsvIncludesScheduleAndExercises() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let repo = ProgramRepository(modelContext: context)
        let program = try repo.createFirstProgram(name: "CSV Export")

        let data = try ProgramSpreadsheetExport.buildCsv(program: program, calendar: .current)
        let text = try #require(String(data: data.dropFirst(3), encoding: .utf8))
        #expect(text.contains("program,CSV Export"))
        #expect(text.contains("Exercise 1"))
        #expect(text.contains("schedule,"))
    }

    // MARK: - TodayViewModel: force today's plan

    /// Forcing today onto a different workout than currently scheduled should cascade every later day forward by
    /// one, exactly like the Program tab's schedule picker — this is what makes "missed a day, resume today" work:
    /// forcing today to what you actually want to do keeps the rest of the rotation's relative order intact.
    @Test func forceTodaysScheduleCascadesLaterDaysAndRefreshesStatus() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let program = PersistedProgram(name: "P")
        let workoutA = PersistedWorkout(name: "Workout A")
        let workoutB = PersistedWorkout(name: "Workout B")
        workoutA.program = program
        workoutB.program = program
        program.workouts.append(contentsOf: [workoutA, workoutB])

        // day0 = A (today), day1 = B, day2 = rest.
        for offset in 0 ..< 3 {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let cd = CalendarDate(from: date, calendar: calendar)
            let workoutID: UUID?
            let isRest: Bool
            switch offset {
            case 0: workoutID = workoutA.id; isRest = false
            case 1: workoutID = workoutB.id; isRest = false
            default: workoutID = nil; isRest = true
            }
            let entry = PersistedScheduleEntry(year: cd.year, month: cd.month, day: cd.day, isRestDay: isRest, workoutID: workoutID)
            entry.program = program
            program.scheduleEntries.append(entry)
        }
        context.insert(program)
        try context.save()

        let viewModel = TodayViewModel(modelContext: context, dateProvider: StubDateProvider(now: today))
        viewModel.refresh()
        #expect(viewModel.status == .workoutDay(workoutId: workoutA.id, title: "Workout A"))
        #expect(Set(viewModel.availableWorkoutsForOverride.map(\.id)) == Set([workoutA.id, workoutB.id]))

        viewModel.forceTodaysSchedule(to: .workout(workoutB.id))

        #expect(viewModel.status == .workoutDay(workoutId: workoutB.id, title: "Workout B"))

        func entry(daysFromToday offset: Int) -> PersistedScheduleEntry? {
            let cd = CalendarDate(from: calendar.date(byAdding: .day, value: offset, to: today)!, calendar: calendar)
            return program.scheduleEntries.first { $0.year == cd.year && $0.month == cd.month && $0.day == cd.day }
        }
        // B was already due tomorrow, so this swaps today <-> tomorrow (today: A -> B, tomorrow: B -> A) rather
        // than shifting the whole horizon: day2 (rest) is untouched, not pushed to a 3rd day of rest.
        #expect(entry(daysFromToday: 0)?.workoutID == workoutB.id)
        #expect(entry(daysFromToday: 1)?.workoutID == workoutA.id)
        #expect(entry(daysFromToday: 2)?.isRestDay == true)
    }

    /// When the forced workout does **not** recur anywhere in the near-term schedule, there's nothing to swap
    /// with, so this falls back to the original insert-and-shift-everything behavior (extending the horizon by
    /// one day) -- the genuine "I missed a day, delay the rest of the rotation to catch up" case.
    @Test func forceTodaysScheduleWithNoNearbyRecurrenceFallsBackToFullShift() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let program = PersistedProgram(name: "P")
        let workoutA = PersistedWorkout(name: "Workout A")
        let workoutB = PersistedWorkout(name: "Workout B")
        let workoutC = PersistedWorkout(name: "Workout C")
        workoutA.program = program
        workoutB.program = program
        workoutC.program = program
        program.workouts.append(contentsOf: [workoutA, workoutB, workoutC])

        // day0 = A (today), day1 = rest. C never appears anywhere in the schedule.
        for offset in 0 ..< 2 {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let cd = CalendarDate(from: date, calendar: calendar)
            let workoutID: UUID?
            let isRest: Bool
            switch offset {
            case 0: workoutID = workoutA.id; isRest = false
            default: workoutID = nil; isRest = true
            }
            let entry = PersistedScheduleEntry(year: cd.year, month: cd.month, day: cd.day, isRestDay: isRest, workoutID: workoutID)
            entry.program = program
            program.scheduleEntries.append(entry)
        }
        context.insert(program)
        try context.save()

        let viewModel = TodayViewModel(modelContext: context, dateProvider: StubDateProvider(now: today))
        viewModel.refresh()
        viewModel.forceTodaysSchedule(to: .workout(workoutC.id))

        func entry(daysFromToday offset: Int) -> PersistedScheduleEntry? {
            let cd = CalendarDate(from: calendar.date(byAdding: .day, value: offset, to: today)!, calendar: calendar)
            return program.scheduleEntries.first { $0.year == cd.year && $0.month == cd.month && $0.day == cd.day }
        }
        #expect(entry(daysFromToday: 0)?.workoutID == workoutC.id)
        // day1 inherits today's old value (A) -- the classic shift, since C never recurs to swap with.
        #expect(entry(daysFromToday: 1)?.workoutID == workoutA.id)
        #expect(entry(daysFromToday: 2)?.isRestDay == true)
    }

    // MARK: - StringSimilarity

    @Test func stringSimilarityIdenticalStringsScoreOne() {
        #expect(StringSimilarity.ratio("bench press", "bench press") == 1.0)
    }

    @Test func stringSimilarityCompletelyDifferentStringsScoreLow() {
        #expect(StringSimilarity.ratio("bench press", "squat") < 0.3)
    }

    @Test func stringSimilarityCloseTypoScoresAboveFuzzyThreshold() {
        // Missing one letter out of 12 ("Bench Press" -> "Bench Pres").
        #expect(StringSimilarity.ratio("bench press", "bench pres") >= ExerciseCarryoverMatcher.fuzzyThreshold)
    }

    // MARK: - ExerciseCarryoverMatcher

    @Test func exerciseCarryoverMatcherAutoMatchesExactNamesCaseInsensitively() {
        let old = [ExerciseCarryoverMatcher.ExistingExercise(id: UUID(), name: "Bench Press")]
        let cycle = [
            XlsxCycleDay(sheetName: "Push 1", isRestDay: false, exercises: [
                XlsxImportedExercise(name: "  bench press  ", note: nil, repsArePerSide: false),
            ]),
        ]
        let result = ExerciseCarryoverMatcher.match(existing: old, newCycle: cycle)
        let ref = ImportExerciseRef(workoutSheetName: "Push 1", exerciseName: "  bench press  ")
        #expect(result.autoCarryover[ref] == old[0].id)
        #expect(result.suggestions.isEmpty)
    }

    @Test func exerciseCarryoverMatcherSuggestsCloseNonExactMatches() {
        let old = [ExerciseCarryoverMatcher.ExistingExercise(id: UUID(), name: "Bench Press")]
        let cycle = [
            XlsxCycleDay(sheetName: "Push 1", isRestDay: false, exercises: [
                XlsxImportedExercise(name: "Bench Pres", note: nil, repsArePerSide: false),
            ]),
        ]
        let result = ExerciseCarryoverMatcher.match(existing: old, newCycle: cycle)
        #expect(result.autoCarryover.isEmpty)
        #expect(result.suggestions.count == 1)
        #expect(result.suggestions.first?.oldExerciseId == old[0].id)
        #expect(result.suggestions.first?.oldExerciseName == "Bench Press")
        #expect(result.suggestions.first?.newExercise.exerciseName == "Bench Pres")
    }

    @Test func exerciseCarryoverMatcherIgnoresUnrelatedNames() {
        let old = [ExerciseCarryoverMatcher.ExistingExercise(id: UUID(), name: "Bench Press")]
        let cycle = [
            XlsxCycleDay(sheetName: "Legs 1", isRestDay: false, exercises: [
                XlsxImportedExercise(name: "Back Squat", note: nil, repsArePerSide: false),
            ]),
        ]
        let result = ExerciseCarryoverMatcher.match(existing: old, newCycle: cycle)
        #expect(result.autoCarryover.isEmpty)
        #expect(result.suggestions.isEmpty)
    }

    @Test func exerciseCarryoverMatcherGreedilyAssignsBestPairsWithoutDoubleClaiming() {
        let benchId = UUID()
        let machineId = UUID()
        let old = [
            ExerciseCarryoverMatcher.ExistingExercise(id: benchId, name: "Bench Press"),
            ExerciseCarryoverMatcher.ExistingExercise(id: machineId, name: "Bench Press Machine"),
        ]
        let cycle = [
            XlsxCycleDay(sheetName: "Push 1", isRestDay: false, exercises: [
                XlsxImportedExercise(name: "Bench Pres", note: nil, repsArePerSide: false),
                XlsxImportedExercise(name: "Bench Press Machin", note: nil, repsArePerSide: false),
            ]),
        ]
        let result = ExerciseCarryoverMatcher.match(existing: old, newCycle: cycle)
        #expect(result.suggestions.count == 2)
        let byNewName = Dictionary(uniqueKeysWithValues: result.suggestions.map { ($0.newExercise.exerciseName, $0.oldExerciseId) })
        #expect(byNewName["Bench Pres"] == benchId)
        #expect(byNewName["Bench Press Machin"] == machineId)
    }

    /// Regression for a real on-device crash: a workbook sheet repeating the exact same exercise name twice
    /// (e.g. a copy-paste duplicate) used to trap `ExerciseCarryoverMatcher.match`'s workbook-order `Dictionary`
    /// on a duplicate key (`Dictionary(uniqueKeysWithValues:)`), crashing the whole app on import.
    @Test func exerciseCarryoverMatcherToleratesDuplicateExerciseNameOnSameSheet() {
        let cycle = [
            XlsxCycleDay(sheetName: "Legs 2", isRestDay: false, exercises: [
                XlsxImportedExercise(name: "Hip adduction", note: nil, repsArePerSide: false),
                XlsxImportedExercise(name: "Hip adduction", note: nil, repsArePerSide: false),
            ]),
        ]
        let result = ExerciseCarryoverMatcher.match(existing: [], newCycle: cycle)
        #expect(result.autoCarryover.isEmpty)
        #expect(result.suggestions.isEmpty)
    }

    // MARK: - Import carryover end to end

    /// Re-importing with an exact exercise-name match should reuse the old exercise's id, which keeps
    /// `WorkoutSessionRepository.mostRecentLoggedValuesByExercise` (and therefore the workout logger's reference
    /// weight hints) finding history logged before the import.
    @Test @MainActor func reimportWithMatchedExerciseNameCarriesOverReferenceWeight() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context

        let program = PersistedProgram(name: "Old Program")
        let workout = PersistedWorkout(name: "Push 1")
        workout.program = program
        program.workouts.append(workout)
        let exercise = PersistedExercise(name: "Bench Press", sortOrder: 0, setCount: 1)
        exercise.workout = workout
        workout.exercises.append(exercise)

        let session = PersistedWorkoutSession(
            workoutTemplateId: workout.id,
            scheduleYear: 2026, scheduleMonth: 1, scheduleDay: 1
        )
        session.isComplete = true
        session.completedAt = Date()
        session.workoutTitleSnapshot = "Push 1"
        let loggedSet = PersistedLoggedSet(exerciseId: exercise.id, setIndex: 0, weight: 100, reps: 5)
        loggedSet.userEditedValues = true
        loggedSet.session = session
        session.loggedSets.append(loggedSet)

        context.insert(program)
        context.insert(session)
        try context.save()

        let oldExerciseId = exercise.id
        let existing = [ExerciseCarryoverMatcher.ExistingExercise(id: oldExerciseId, name: "Bench Press")]
        let newCycle = [
            XlsxCycleDay(sheetName: "Push 1", isRestDay: false, exercises: [
                XlsxImportedExercise(name: "Bench Press", note: nil, repsArePerSide: false),
            ]),
        ]
        let matchResult = ExerciseCarryoverMatcher.match(existing: existing, newCycle: newCycle)
        #expect(matchResult.autoCarryover.count == 1)

        try ProgramXlsxImporter.importReplacingStore(
            cycle: newCycle,
            programName: "New Program",
            startDate: CalendarDate(year: 2026, month: 1, day: 2),
            modelContext: context,
            horizonDays: 3,
            exerciseCarryover: matchResult.autoCarryover
        )

        let newProgram = try #require(try ProgramRepository(modelContext: context).activeProgram())
        let newExercise = try #require(newProgram.workouts.first?.exercises.first)
        #expect(newExercise.id == oldExerciseId)

        let referenceValues = try WorkoutSessionRepository(modelContext: context).mostRecentLoggedValuesByExercise()
        #expect(referenceValues[oldExerciseId]?[0]?.weight == 100)
        #expect(referenceValues[oldExerciseId]?[0]?.reps == 5)

        // History for the old session should also resolve the exercise name via the current program's carried-over id,
        // even though the workout template it was originally logged under is gone.
        let detail = try #require(try HistoryRepository(modelContext: context).sessionDetail(sessionId: session.id))
        #expect(detail.exercises.first?.name == "Bench Press")
    }

    @Test @MainActor func reimportWithUnmatchedExerciseNameGetsFreshIdAndNoReference() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context

        let program = PersistedProgram(name: "Old Program")
        let workout = PersistedWorkout(name: "Push 1")
        workout.program = program
        program.workouts.append(workout)
        let exercise = PersistedExercise(name: "Bench Press", sortOrder: 0, setCount: 1)
        exercise.workout = workout
        workout.exercises.append(exercise)
        context.insert(program)
        try context.save()

        // No carryover map supplied — matches the default `importReplacingStore` behavior before this feature existed.
        let newCycle = [
            XlsxCycleDay(sheetName: "Push 1", isRestDay: false, exercises: [
                XlsxImportedExercise(name: "Overhead Press", note: nil, repsArePerSide: false),
            ]),
        ]
        try ProgramXlsxImporter.importReplacingStore(
            cycle: newCycle,
            programName: "New Program",
            startDate: CalendarDate(year: 2026, month: 1, day: 2),
            modelContext: context,
            horizonDays: 3
        )

        let newProgram = try #require(try ProgramRepository(modelContext: context).activeProgram())
        let newExercise = try #require(newProgram.workouts.first?.exercises.first)
        #expect(newExercise.id != exercise.id)
    }

    // MARK: - Cardio exercises

    @Test func setExerciseKindPersists() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let program = PersistedProgram(name: "P")
        let workout = PersistedWorkout(name: "Cardio")
        workout.program = program
        program.workouts.append(workout)
        let exercise = PersistedExercise(name: "Run", sortOrder: 0, setCount: 1)
        exercise.workout = workout
        workout.exercises.append(exercise)
        context.insert(program)
        try context.save()

        #expect(exercise.kind == .strength)
        let repo = ProgramRepository(modelContext: context)
        try repo.setExerciseKind(id: exercise.id, kind: .cardio)
        #expect(exercise.kind == .cardio)
    }

    /// Cardio is normally a single set (one duration/heart-rate reading), not a strength-style multi-set default —
    /// switching an exercise to cardio should reset its set count to 1, not leave it at whatever strength default it had.
    @Test func setExerciseKindResetsSetCountToOneWhenSwitchingToCardio() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let program = PersistedProgram(name: "P")
        let workout = PersistedWorkout(name: "Push 1")
        workout.program = program
        program.workouts.append(workout)
        let exercise = PersistedExercise(name: "Bench Press", sortOrder: 0, setCount: 4)
        exercise.workout = workout
        workout.exercises.append(exercise)
        context.insert(program)
        try context.save()

        let repo = ProgramRepository(modelContext: context)
        try repo.setExerciseKind(id: exercise.id, kind: .cardio)
        #expect(exercise.setCount == 1)

        // Switching back to strength doesn't second-guess the (now 1) count — the user adjusts it if they want more.
        try repo.setExerciseKind(id: exercise.id, kind: .strength)
        #expect(exercise.setCount == 1)
    }

    @Test func updateCardioLoggedSetRecordsMinutesAndMaxHeartRateAndClampsNegatives() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let program = PersistedProgram(name: "P")
        let workout = PersistedWorkout(name: "Cardio")
        workout.program = program
        program.workouts.append(workout)
        let exercise = PersistedExercise(name: "Run", sortOrder: 0, setCount: 1, kind: .cardio)
        exercise.workout = workout
        workout.exercises.append(exercise)
        context.insert(program)
        try context.save()

        let day = CalendarDate(from: Date(), calendar: .current)
        let repo = WorkoutSessionRepository(modelContext: context)
        let session = try repo.getOrCreateActiveSession(templateId: workout.id, day: day, workout: workout)

        try repo.updateCardioLoggedSet(session: session, exerciseId: exercise.id, setIndex: 0, minutes: -5, maxHeartRate: -10)
        let row = try #require(session.loggedSets.first)
        #expect(row.cardioMinutes == 0)
        #expect(row.maxHeartRate == 0)
        #expect(row.userEditedValues == true)

        try repo.updateCardioLoggedSet(session: session, exerciseId: exercise.id, setIndex: 0, minutes: 22.5, maxHeartRate: 158)
        #expect(row.cardioMinutes == 22.5)
        #expect(row.maxHeartRate == 158)
        // Strength fields stay untouched by the cardio update.
        #expect(row.weight == 0)
        #expect(row.reps == 0)
    }

    @Test func workoutTemplateEditorPersistsExerciseKind() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let repo = ProgramRepository(modelContext: context)
        let program = try repo.createFirstProgram(name: "Test")
        let workout = try #require(program.workouts.first)
        let outline = try #require(try ProgramOutlineRepository(modelContext: context).activeProgramOutline())
        let workoutOutline = try #require(outline.workouts.first(where: { $0.id == workout.id }))

        let editor = WorkoutTemplateEditorViewModel(modelContext: context)
        editor.present(workout: workoutOutline)
        #expect(editor.rows.first?.kind == .strength)

        let exerciseId = try #require(editor.rows.first?.id)
        editor.persistExerciseKind(exerciseId: exerciseId, kind: .cardio)

        let refreshed = try #require(try ProgramOutlineRepository(modelContext: context).activeProgramOutline())
        let refreshedExercise = try #require(refreshed.workouts.first?.exercises.first)
        #expect(refreshedExercise.kind == .cardio)
    }

    @Test @MainActor func workoutLoggingViewModelShowsCardioReferenceValuesAndPersistsEntry() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context

        let program = PersistedProgram(name: "P")
        let workout = PersistedWorkout(name: "Cardio")
        workout.program = program
        program.workouts.append(workout)
        let exercise = PersistedExercise(name: "Run", sortOrder: 0, setCount: 1, kind: .cardio)
        exercise.workout = workout
        workout.exercises.append(exercise)

        // A prior completed session supplies the reference (last time's) minutes/max heart rate.
        let priorSession = PersistedWorkoutSession(
            workoutTemplateId: workout.id, scheduleYear: 2026, scheduleMonth: 1, scheduleDay: 1
        )
        priorSession.isComplete = true
        priorSession.completedAt = Date().addingTimeInterval(-86400)
        let priorSet = PersistedLoggedSet(exerciseId: exercise.id, setIndex: 0, cardioMinutes: 20, maxHeartRate: 150)
        priorSet.userEditedValues = true
        priorSet.session = priorSession
        priorSession.loggedSets.append(priorSet)

        context.insert(program)
        context.insert(priorSession)
        try context.save()

        let router = AppRouter()
        router.selectedWorkoutId = workout.id
        let viewModel = WorkoutLoggingViewModel(modelContext: context, router: router, dateProvider: StubDateProvider(now: Date()))
        viewModel.loadFromRouter()

        let section = try #require(viewModel.sections.first)
        #expect(section.kind == .cardio)
        let row = try #require(section.rows.first)
        #expect(row.referenceCardioMinutes == 20)
        #expect(row.referenceMaxHeartRate == 150)
        #expect(row.isEntered == false)

        viewModel.updateCardioLoggedSet(exerciseId: exercise.id, setIndex: 0, minutes: 25, maxHeartRate: 162, markUserEntry: true)
        let enteredRow = try #require(viewModel.sections.first?.rows.first)
        #expect(enteredRow.isEntered == true)
        #expect(enteredRow.cardioMinutes == 25)
        #expect(enteredRow.maxHeartRate == 162)

        // Cardio sets don't contribute to weight×reps session volume.
        #expect(viewModel.sessionVolume == 0)
    }

    @Test @MainActor func historySessionDetailExcludesCardioFromVolumeAndKeepsMinutesAndHeartRate() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context

        let program = PersistedProgram(name: "P")
        let workout = PersistedWorkout(name: "Mixed")
        workout.program = program
        program.workouts.append(workout)
        let strength = PersistedExercise(name: "Bench", sortOrder: 0, setCount: 1)
        strength.workout = workout
        let cardio = PersistedExercise(name: "Run", sortOrder: 1, setCount: 1, kind: .cardio)
        cardio.workout = workout
        workout.exercises.append(contentsOf: [strength, cardio])

        let session = PersistedWorkoutSession(
            workoutTemplateId: workout.id, scheduleYear: 2026, scheduleMonth: 1, scheduleDay: 1
        )
        session.isComplete = true
        session.completedAt = Date()
        session.workoutTitleSnapshot = "Mixed"
        let strengthSet = PersistedLoggedSet(exerciseId: strength.id, setIndex: 0, weight: 100, reps: 5)
        strengthSet.userEditedValues = true
        strengthSet.session = session
        let cardioSet = PersistedLoggedSet(exerciseId: cardio.id, setIndex: 0, cardioMinutes: 30, maxHeartRate: 170)
        cardioSet.userEditedValues = true
        cardioSet.session = session
        session.loggedSets.append(contentsOf: [strengthSet, cardioSet])

        context.insert(program)
        context.insert(session)
        try context.save()

        let detail = try #require(try HistoryRepository(modelContext: context).sessionDetail(sessionId: session.id))
        #expect(detail.totalVolume == 500) // 100 * 5 from the strength set only.

        let cardioGroup = try #require(detail.exercises.first { $0.name == "Run" })
        #expect(cardioGroup.volume == 0)
        let cardioLine = try #require(cardioGroup.sets.first)
        #expect(cardioLine.kind == .cardio)
        #expect(cardioLine.cardioMinutes == 30)
        #expect(cardioLine.maxHeartRate == 170)

        let strengthGroup = try #require(detail.exercises.first { $0.name == "Bench" })
        #expect(strengthGroup.volume == 500)
    }

    @Test func historySpreadsheetExportIncludesCardioColumns() throws {
        let session = HistorySessionDetail(
            id: UUID(),
            completedAt: Date(),
            workoutTitle: "Cardio Day",
            totalVolume: 0,
            scheduleDayLabel: nil,
            sessionNote: nil,
            exercises: [
                HistorySessionExerciseGroup(
                    exerciseId: UUID(),
                    name: "Run",
                    volume: 0,
                    sets: [
                        HistorySessionSetLine(
                            exerciseId: UUID(),
                            setIndex: 0,
                            setNumber: 1,
                            weight: 0,
                            reps: 0,
                            repsArePerSide: false,
                            kind: .cardio,
                            cardioMinutes: 30,
                            maxHeartRate: 170
                        ),
                    ]
                ),
            ]
        )
        let csvData = try HistorySpreadsheetExport.buildCsv(sessions: [session])
        let csvText = try #require(String(data: csvData.dropFirst(3), encoding: .utf8))
        #expect(csvText.contains("cardio,30.0,170"))

        let xlsxData = try HistorySpreadsheetExport.buildXlsx(sessions: [session])
        let sheetXml = try XlsxArchiveReader.extract("xl/worksheets/sheet1.xml", fromXlsx: xlsxData)
        let sheetText = try #require(String(data: sheetXml, encoding: .utf8))
        #expect(sheetText.contains("cardio"))
    }

    @Test func programSpreadsheetExportIncludesExerciseType() throws {
        let store = try Self.makeInMemoryStore()
        let context = store.context
        let repo = ProgramRepository(modelContext: context)
        let program = try repo.createFirstProgram(name: "Type Export")
        let workout = try #require(program.workouts.first)
        let exercise = try #require(workout.exercises.first)
        try repo.setExerciseKind(id: exercise.id, kind: .cardio)

        let data = try ProgramSpreadsheetExport.buildXlsx(program: program)
        let sheetXml = try XlsxArchiveReader.extract("xl/worksheets/sheet1.xml", fromXlsx: data)
        let sheetText = try #require(String(data: sheetXml, encoding: .utf8))
        #expect(sheetText.contains("cardio"))
    }

    // MARK: - Cardio spreadsheet import (Minutes / Peak HR section header)

    @Test func cardioSectionHeaderRowFindsMinutesPeakHrPair() {
        let cells: [String: String] = [
            "A1": "Excercise_Name", "B1": "Per side", "C1": "Notes",
            "A2": "Bench Press",
            "B10": "Minutes", "C10": "Peak HR",
            "A11": "Cardio",
        ]
        #expect(ProgramXlsxParser.cardioSectionHeaderRow(cells: cells) == 10)
    }

    @Test func cardioSectionHeaderRowAcceptsSynonymsAndIsNilWhenAbsent() {
        let withSynonym: [String: String] = ["B5": "Min", "C5": "Max HR"]
        #expect(ProgramXlsxParser.cardioSectionHeaderRow(cells: withSynonym) == 5)

        let withoutSection: [String: String] = ["A1": "Excercise_Name", "A2": "Bench Press"]
        #expect(ProgramXlsxParser.cardioSectionHeaderRow(cells: withoutSection) == nil)
    }

    @Test func exercisesFromCellsExcludesRowsAtOrPastCardioHeader() {
        let cells: [String: String] = [
            "A1": "Excercise_Name", "B1": "Per side", "C1": "Notes",
            "A2": "Bench Press", "B2": "x",
            "A3": "Barbell Row",
            "B10": "Minutes", "C10": "Peak HR",
            "A11": "Cardio",
        ]
        let strength = ProgramXlsxParser.exercisesFromCells(cells, beforeRow: 10)
        #expect(strength.count == 2)
        #expect(strength.allSatisfy { $0.kind == .strength })
        #expect(strength.map(\.name) == ["Bench Press", "Barbell Row"])
    }

    @Test func parsesSheetWithStrengthRowsThenTrailingCardioSet() throws {
        // Mirrors the "Push 1" tab in Set Buddy-4.xlsx: strength rows, then a Minutes/Peak HR
        // header, then one cardio row — a lift day finished with a cardio set.
        let cells: [String: String] = [
            "A1": "Excercise_Name", "B1": "Per side", "C1": "Notes",
            "A2": "Bench Press", "B2": "x",
            "A3": "Barbell Row",
            "B4": "Minutes", "C4": "Peak HR",
            "A5": "Cardio",
        ]
        let cardioRow = try #require(ProgramXlsxParser.cardioSectionHeaderRow(cells: cells))
        let strength = ProgramXlsxParser.exercisesFromCells(cells, beforeRow: cardioRow)
        #expect(strength.map(\.name) == ["Bench Press", "Barbell Row"])
        #expect(strength.allSatisfy { $0.kind == .strength })
    }

    @Test func parsesSetBuddy4Fixture_cardioSectionsAndWholeCardioDays() throws {
        let bundle = Bundle(for: SetBuddy4FixtureToken.self)
        guard let url = bundle.url(forResource: "Set Buddy-4", withExtension: "xlsx") else {
            Issue.record("Add Fixtures/Set Buddy-4.xlsx to the Set BuddyTests folder (synced into the test bundle).")
            return
        }
        let data = try Data(contentsOf: url)
        let cycle = try ProgramXlsxParser.parse(xlsxData: data)

        // "Push 1": 8 strength exercises, then a trailing "Cardio" set.
        let push1 = try #require(cycle.first { $0.sheetName == "Push 1" })
        #expect(push1.isRestDay == false)
        #expect(push1.exercises.count == 9)
        let push1Strength = push1.exercises.dropLast()
        #expect(push1Strength.allSatisfy { $0.kind == .strength })
        let push1Last = try #require(push1.exercises.last)
        #expect(push1Last.kind == .cardio)
        #expect(push1Last.name == "Cardio")

        // "Cardio 1": a whole cardio day — not a rest day despite having no strength rows.
        let cardio1 = try #require(cycle.first { $0.sheetName == "Cardio 1" })
        #expect(cardio1.isRestDay == false)
        #expect(cardio1.exercises.count == 1)
        #expect(cardio1.exercises[0].kind == .cardio)
        #expect(cardio1.exercises[0].name == "Cardio")

        // "Rest 1": genuinely empty, still a rest day.
        let rest1 = try #require(cycle.first { $0.sheetName == "Rest 1" })
        #expect(rest1.isRestDay == true)
    }

    @Test @MainActor func importsSetBuddy4Fixture_cardioKindOnPersistedTemplates() throws {
        let bundle = Bundle(for: SetBuddy4FixtureToken.self)
        guard let url = bundle.url(forResource: "Set Buddy-4", withExtension: "xlsx") else {
            Issue.record("Add Fixtures/Set Buddy-4.xlsx to the Set BuddyTests folder (synced into the test bundle).")
            return
        }
        let data = try Data(contentsOf: url)
        let store = try Self.makeInMemoryStore()
        let context = store.context

        try ProgramXlsxImporter.importReplacingStore(
            xlsx: data,
            programName: "Cardio Import",
            startDate: CalendarDate(year: 2026, month: 1, day: 1),
            modelContext: context,
            horizonDays: 12
        )

        let program = try #require(try ProgramRepository(modelContext: context).activeProgram())
        let push1 = try #require(program.workouts.first { $0.name == "Push 1" })
        let sorted = push1.exercises.sorted { $0.sortOrder < $1.sortOrder }
        #expect(sorted.dropLast().allSatisfy { $0.kind == .strength })
        #expect(sorted.last?.kind == .cardio)
        #expect(sorted.last?.name == "Cardio")
        // Cardio defaults to a single set on import (a strength default of 4 doesn't make sense for it).
        #expect(sorted.last?.setCount == 1)
        #expect(sorted.dropLast().allSatisfy { $0.setCount == ProgramXlsxParser.defaultSetCountPerExercise })

        let cardio1 = try #require(program.workouts.first { $0.name == "Cardio 1" })
        #expect(cardio1.exercises.allSatisfy { $0.kind == .cardio })
        #expect(cardio1.exercises.allSatisfy { $0.setCount == 1 })
    }

    /// Regression for a real report: the Program tab's per-day schedule picker (`ProgramOutlineRepository`'s
    /// workout order) grouped every cardio workout at the end of the list instead of showing them interleaved
    /// where they actually fall in the spreadsheet's cycle -- because ordering fell back entirely to
    /// `WorkoutTemplateDisplaySort`'s Push/Pull/Legs-only naming heuristic, which has no idea where "Cardio 1"
    /// belongs and parks anything unrecognized at the end. Workouts must now come back in the spreadsheet's
    /// actual interleaved cycle order.
    @Test @MainActor func importsSetBuddy4Fixture_workoutOrderMatchesSpreadsheetCycleNotNamingHeuristic() throws {
        let bundle = Bundle(for: SetBuddy4FixtureToken.self)
        guard let url = bundle.url(forResource: "Set Buddy-4", withExtension: "xlsx") else {
            Issue.record("Add Fixtures/Set Buddy-4.xlsx to the Set BuddyTests folder (synced into the test bundle).")
            return
        }
        let data = try Data(contentsOf: url)
        let store = try Self.makeInMemoryStore()
        let context = store.context

        try ProgramXlsxImporter.importReplacingStore(
            xlsx: data,
            programName: "Cardio Import",
            startDate: CalendarDate(year: 2026, month: 1, day: 1),
            modelContext: context,
            horizonDays: 12
        )

        let outline = try #require(try ProgramOutlineRepository(modelContext: context).activeProgramOutline())
        #expect(outline.workouts.map(\.name) == [
            "Push 1", "Cardio 1", "Pull 1", "Cardio 2", "Legs 1",
            "Push 2", "Cardio 3", "Pull 2", "Cardio 4", "Legs 2",
        ])
    }

    /// Exercises the exact same code the real Settings import UI calls (`ImportViewModel`), not just the
    /// lower-level parser/importer — including the real default 196-day horizon — to reproduce a reported
    /// on-device crash when importing `Set Buddy-4.xlsx`.
    @Test @MainActor func reproduceRealImportViewModelFlowWithSetBuddy4Fixture() async throws {
        let bundle = Bundle(for: SetBuddy4FixtureToken.self)
        guard let url = bundle.url(forResource: "Set Buddy-4", withExtension: "xlsx") else {
            Issue.record("Add Fixtures/Set Buddy-4.xlsx to the Set BuddyTests folder (synced into the test bundle).")
            return
        }
        let store = try Self.makeInMemoryStore()
        let context = store.context

        let importer = ImportViewModel()
        importer.stageImportFromPickedFile(url: url, modelContext: context)
        #expect(importer.importError == nil)
        #expect(importer.importStagingPresented == true)

        await importer.confirmStagedImport(modelContext: context)
        #expect(importer.importError == nil, "importError: \(importer.importError ?? "nil")")

        let program = try #require(try ProgramRepository(modelContext: context).activeProgram())
        #expect(program.scheduleEntries.count > 0)
    }
}

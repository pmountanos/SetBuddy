//
//  PersistedProgramModels.swift
//  Set Buddy
//

import Foundation
import SwiftData

@Model
final class PersistedProgram {
    var name: String
    @Relationship(deleteRule: .cascade, inverse: \PersistedWorkout.program)
    var workouts: [PersistedWorkout]
    @Relationship(deleteRule: .cascade, inverse: \PersistedScheduleEntry.program)
    var scheduleEntries: [PersistedScheduleEntry]

    init(name: String) {
        self.name = name
        self.workouts = []
        self.scheduleEntries = []
    }
}

@Model
final class PersistedWorkout {
    var id: UUID
    var name: String
    var program: PersistedProgram?
    /// Display/picker order: the workout's first-encountered position in the imported spreadsheet's cycle
    /// (interleaved, e.g. Push 1, Cardio 1, Pull 1, Cardio 2, ...), or append order for workouts added in-app.
    /// Ties (e.g. every workout defaulting to 0 on an install that predates this field) fall back to
    /// `WorkoutTemplateDisplaySort`'s naming heuristic — see its call sites.
    ///
    /// The `= 0` here (not just on `init`'s parameter) is required for SwiftData's lightweight migration: it's
    /// what tells SwiftData how to backfill this new column for rows that existed before this field did.
    /// Without it, opening an existing store crashed `ModelContainer` init on launch (confirmed via the
    /// on-device crash log — `_assertionFailure` inside `Set_BuddyApp.sharedModelContainer`).
    var sortOrder: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \PersistedExercise.workout)
    var exercises: [PersistedExercise]

    init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.exercises = []
    }
}

@Model
final class PersistedScheduleEntry {
    var year: Int
    var month: Int
    var day: Int
    var isRestDay: Bool
    var workoutID: UUID?
    var program: PersistedProgram?

    init(year: Int, month: Int, day: Int, isRestDay: Bool, workoutID: UUID?) {
        self.year = year
        self.month = month
        self.day = day
        self.isRestDay = isRestDay
        self.workoutID = workoutID
    }
}

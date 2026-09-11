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
    @Relationship(deleteRule: .cascade, inverse: \PersistedExercise.workout)
    var exercises: [PersistedExercise]

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
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

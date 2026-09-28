//
//  PersistedWorkoutLoggingModels.swift
//  Set Buddy
//

import Foundation
import SwiftData

@Model
final class PersistedExercise {
    var id: UUID
    var name: String
    var sortOrder: Int
    /// Number of sets to log for this exercise in a session.
    var setCount: Int
    /// Optional coaching note (e.g. from spreadsheet); shown when the user taps the exercise name while logging.
    var note: String?
    /// When true, logged reps are **per side** (e.g. dumbbell); volume for each set counts both sides (×2).
    var repsArePerSide: Bool
    /// Strength (weight/reps) or cardio (minutes/max heart rate). Drives which fields the logger shows.
    var kind: ExerciseKind
    var workout: PersistedWorkout?

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        setCount: Int,
        note: String? = nil,
        repsArePerSide: Bool = false,
        kind: ExerciseKind = .strength
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.setCount = setCount
        self.note = note
        self.repsArePerSide = repsArePerSide
        self.kind = kind
    }
}

@Model
final class PersistedWorkoutSession {
    var id: UUID
    /// Matches `PersistedWorkout.id` for the template being performed.
    var workoutTemplateId: UUID
    var scheduleYear: Int
    var scheduleMonth: Int
    var scheduleDay: Int
    var isComplete: Bool
    var createdAt: Date
    /// Set when the user finishes the session; used for history ordering.
    var completedAt: Date?
    /// Workout name at completion time so history stays correct after program re-import removes old templates.
    var workoutTitleSnapshot: String?
    /// Optional user note for this session (in progress or completed); shown and editable in History.
    var sessionNote: String?
    @Relationship(deleteRule: .cascade, inverse: \PersistedLoggedSet.session)
    var loggedSets: [PersistedLoggedSet]

    init(
        id: UUID = UUID(),
        workoutTemplateId: UUID,
        scheduleYear: Int,
        scheduleMonth: Int,
        scheduleDay: Int
    ) {
        self.id = id
        self.workoutTemplateId = workoutTemplateId
        self.scheduleYear = scheduleYear
        self.scheduleMonth = scheduleMonth
        self.scheduleDay = scheduleDay
        self.isComplete = false
        self.createdAt = Date()
        self.completedAt = nil
        self.workoutTitleSnapshot = nil
        self.sessionNote = nil
        self.loggedSets = []
    }
}

@Model
final class PersistedLoggedSet {
    var exerciseId: UUID
    var setIndex: Int
    var weight: Double
    var reps: Int
    /// Cardio-exercise values (unused/zero for strength sets).
    var cardioMinutes: Double
    var maxHeartRate: Int
    /// True when weight/reps were copied from the last completed session for this template.
    var seededFromCarryover: Bool
    /// True after the user changes weight or reps for this set in the current session.
    var userEditedValues: Bool
    /// Copied from the exercise template when the row is created; drives volume (×2 when per-side reps).
    var repsArePerSide: Bool
    var session: PersistedWorkoutSession?

    init(
        exerciseId: UUID,
        setIndex: Int,
        weight: Double = 0,
        reps: Int = 0,
        cardioMinutes: Double = 0,
        maxHeartRate: Int = 0,
        seededFromCarryover: Bool = false,
        repsArePerSide: Bool = false
    ) {
        self.exerciseId = exerciseId
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.cardioMinutes = cardioMinutes
        self.maxHeartRate = maxHeartRate
        self.seededFromCarryover = seededFromCarryover
        self.userEditedValues = false
        self.repsArePerSide = repsArePerSide
    }
}

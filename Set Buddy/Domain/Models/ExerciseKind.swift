//
//  ExerciseKind.swift
//  Set Buddy
//

import Foundation

/// What an exercise logs: weight/reps (default) or minutes/max heart rate.
enum ExerciseKind: String, Codable, Sendable, Hashable, CaseIterable {
    case strength
    case cardio
}

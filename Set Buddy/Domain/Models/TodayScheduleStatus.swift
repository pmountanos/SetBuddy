//
//  TodayScheduleStatus.swift
//  Set Buddy
//

import Foundation

enum TodayScheduleStatus: Equatable, Sendable {
    case noProgram
    case dayNotScheduled
    case restDay
    case workoutDay(workoutId: UUID, title: String)
    /// Same scheduled workout as `workoutDay`, but an incomplete session exists for today (user can continue logging).
    case workoutInProgress(workoutId: UUID, title: String)
    /// Scheduled workout for today is already finished; hide the Start action.
    case workoutAlreadyFinished(title: String)
}

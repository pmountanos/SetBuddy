//
//  ScheduledDayKind.swift
//  Set Buddy
//

import Foundation

/// What the program assigns to a single calendar date.
enum ScheduledDayKind: Hashable, Codable, Sendable {
    case rest
    /// The workout template/instance scheduled for that calendar day.
    case workout(workoutId: UUID)
}

//
//  ProgramCalendarSchedule.swift
//  Set Buddy
//

import Foundation

/// Program schedule stored as explicit calendar dates (not abstract weekdays).
/// Each key is one calendar day; the value is rest or a specific workout.
struct ProgramCalendarSchedule: Equatable, Sendable {
    private var days: [CalendarDate: ScheduledDayKind]

    init(days: [CalendarDate: ScheduledDayKind]) {
        self.days = days
    }

    init() {
        self.days = [:]
    }

    /// How this date is scheduled, if the program defines it.
    /// `nil` means this calendar day is outside defined schedule data (import range, program bounds, etc.).
    func scheduledKind(on date: CalendarDate) -> ScheduledDayKind? {
        days[date]
    }

    mutating func set(_ kind: ScheduledDayKind, on date: CalendarDate) {
        days[date] = kind
    }

    mutating func remove(date: CalendarDate) {
        days.removeValue(forKey: date)
    }

    var allEntries: [(date: CalendarDate, kind: ScheduledDayKind)] {
        days.keys.sorted().compactMap { date in
            days[date].map { (date, $0) }
        }
    }
}

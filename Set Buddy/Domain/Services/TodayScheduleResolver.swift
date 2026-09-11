//
//  TodayScheduleResolver.swift
//  Set Buddy
//

import Foundation

enum TodayScheduleResolver {
    /// Resolves “right now” using calendar-date schedule entries and workout titles.
    static func status(
        now: Date,
        calendar: Calendar,
        schedule: ProgramCalendarSchedule,
        workoutNames: [UUID: String]
    ) -> TodayScheduleStatus {
        let today = CalendarDate(from: now, calendar: calendar)
        guard let kind = schedule.scheduledKind(on: today) else {
            return .dayNotScheduled
        }
        switch kind {
        case .rest:
            return .restDay
        case .workout(let id):
            let title = workoutNames[id] ?? "Workout"
            return .workoutDay(workoutId: id, title: title)
        }
    }
}

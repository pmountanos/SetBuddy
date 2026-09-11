//
//  CalendarDate.swift
//  Set Buddy
//

import Foundation

/// A calendar day in the user's locale, independent of time-of-day.
/// Used as the canonical key for program schedule entries.
struct CalendarDate: Hashable, Comparable, Codable, Sendable {
    var year: Int
    /// 1...12
    var month: Int
    /// 1...31 (caller should use `Calendar` when converting to `Date` to validate)
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Derives the local calendar date for `date` using the given `calendar` (pass `Calendar.current` from the main actor at the UI boundary).
    init(from date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year ?? 0
        self.month = c.month ?? 0
        self.day = c.day ?? 0
    }

    /// Start of this calendar day in the given calendar/time zone.
    func startOfDay(using calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components).flatMap { calendar.startOfDay(for: $0) }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(year)
        hasher.combine(month)
        hasher.combine(day)
    }

    static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    /// Adds `days` to this calendar date using `calendar` (typically `Calendar.current` from the main actor).
    func addingDays(_ days: Int, calendar: Calendar) -> CalendarDate? {
        guard let start = startOfDay(using: calendar),
              let next = calendar.date(byAdding: .day, value: days, to: start)
        else { return nil }
        return CalendarDate(from: next, calendar: calendar)
    }
}

//
//  DailyNotificationScheduler.swift
//  Set Buddy
//

import Foundation
import SwiftData
import UserNotifications

@MainActor
final class DailyNotificationScheduler {
    static let shared = DailyNotificationScheduler()

    private let identifierPrefix = "net.mountanos.setbuddy.schedule."

    private init() {}

    /// Fire-and-forget entry point for code that changed something affecting the schedule (program, calendar, a completed
    /// session, or notification prefs). The single place every call site should use instead of wrapping `reschedule(modelContext:)`
    /// in its own `Task` — keeps “remember to reschedule after this mutation” from being repeated at every call site.
    static func requestReschedule(modelContext: ModelContext) {
        Task { @MainActor in
            await shared.reschedule(modelContext: modelContext)
        }
    }

    /// Schedules one local notification per calendar day for the next `horizonDays`, using the same date-based schedule as the Today screen.
    func reschedule(modelContext: ModelContext, horizonDays: Int = 14) async {
        let center = UNUserNotificationCenter.current()

        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)

        let prefs = NotificationSettings.load()
        guard prefs.dailyRemindersEnabled else { return }

        let auth = await center.notificationSettings()
        guard auth.authorizationStatus == .authorized || auth.authorizationStatus == .provisional else { return }

        let calendar = Calendar.current
        let repo = ProgramRepository(modelContext: modelContext)
        guard let program = try? repo.activeProgram() else { return }
        let schedule = repo.calendarSchedule(for: program)
        let titles = repo.workoutTitles(for: program)
        let start = calendar.startOfDay(for: Date())

        for offset in 0 ..< horizonDays {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let cd = CalendarDate(from: dayDate, calendar: calendar)
            let status = TodayScheduleResolver.status(
                now: dayDate,
                calendar: calendar,
                schedule: schedule,
                workoutNames: titles
            )
            let content = Self.notificationContent(for: status)
            let triggerComponents = DateComponents(
                calendar: calendar,
                year: cd.year,
                month: cd.month,
                day: cd.day,
                hour: prefs.hour,
                minute: prefs.minute
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

            let id = "\(identifierPrefix)\(cd.year)-\(cd.month)-\(cd.day)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    private static func notificationContent(for status: TodayScheduleStatus) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        switch status {
        case .noProgram:
            content.title = "Set Buddy"
            content.body = "Set up your training program in the app."
        case .dayNotScheduled:
            content.title = "Set Buddy"
            content.body = "Open the app to see your plan."
        case .restDay:
            content.title = "Rest day"
            content.body = "Today is a scheduled rest day."
        case .workoutDay(_, let title), .workoutInProgress(_, let title):
            content.title = "Workout day"
            content.body = "Today: \(title)."
        case .workoutAlreadyFinished:
            content.title = "Set Buddy"
            content.body = "You’re all set for today’s planned session."
        }
        return content
    }
}

//
//  TodayViewModel.swift
//  Set Buddy
//

import Foundation
import SwiftData

@MainActor
@Observable
final class TodayViewModel {
    private let modelContext: ModelContext
    private let dateProvider: DateProviding

    var status: TodayScheduleStatus?
    var loadError: String?

    init(modelContext: ModelContext, dateProvider: DateProviding = SystemDateProvider()) {
        self.modelContext = modelContext
        self.dateProvider = dateProvider
    }

    func refresh() {
        loadError = nil
        let calendar = Calendar.current
        let repo = ProgramRepository(modelContext: modelContext)
        do {
            if UITestLaunch.isUITesting {
                try ProgramRepository.seedIfNeeded(modelContext: modelContext)
            }
            try ProgramRepository.addExerciseTemplatesIfMissing(modelContext: modelContext)
            try repo.ensureForwardScheduleFilled()
            guard let program = try repo.activeProgram() else {
                status = .noProgram
                return
            }
            let schedule = repo.calendarSchedule(for: program)
            let names = repo.workoutTitles(for: program)
            var resolved = TodayScheduleResolver.status(
                now: dateProvider.now,
                calendar: calendar,
                schedule: schedule,
                workoutNames: names
            )
            if case .workoutDay(let workoutId, let title) = resolved {
                let today = CalendarDate(from: dateProvider.now, calendar: calendar)
                let sessionRepo = WorkoutSessionRepository(modelContext: modelContext)
                if try sessionRepo.hasCompletedSession(templateId: workoutId, day: today) {
                    resolved = .workoutAlreadyFinished(title: title)
                } else if try sessionRepo.activeSession(templateId: workoutId, day: today) != nil {
                    resolved = .workoutInProgress(workoutId: workoutId, title: title)
                }
            }
            status = resolved
        } catch {
            loadError = error.localizedDescription
            status = nil
        }
        DailyNotificationScheduler.requestReschedule(modelContext: modelContext)
    }

    var headline: String {
        guard let status else { return "Loading…" }
        switch status {
        case .noProgram: return "No program"
        case .dayNotScheduled: return "Not on schedule"
        case .restDay: return "Rest day"
        case .workoutDay(_, let title): return title
        case .workoutInProgress(_, let title): return title
        case .workoutAlreadyFinished(let title): return title
        }
    }

    var detail: String {
        guard let status else { return "Checking your calendar…" }
        switch status {
        case .noProgram: return "Create a program on the Program tab (no spreadsheet required), or import one from Settings."
        case .dayNotScheduled: return "This date isn’t on your program calendar yet."
        case .restDay: return "Recovery is part of training."
        case .workoutDay: return "Start below when you’re ready to log sets."
        case .workoutInProgress: return "You have a session in progress. Continue on the Workout tab or below."
        case .workoutAlreadyFinished: return "You’ve already logged this session today. It stays in History."
        }
    }

    var symbolName: String {
        guard let status else { return "ellipsis.circle" }
        switch status {
        case .noProgram: return "tray"
        case .dayNotScheduled: return "calendar.badge.questionmark"
        case .restDay: return "moon.zzz.fill"
        case .workoutDay: return "figure.strengthtraining.traditional"
        case .workoutInProgress: return "figure.strengthtraining.traditional"
        case .workoutAlreadyFinished: return "checkmark.circle.fill"
        }
    }
}

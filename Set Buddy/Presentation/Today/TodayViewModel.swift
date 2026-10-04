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

    /// Workouts offered by “Change today’s plan” (Rest + each workout, same order as the Program tab).
    var availableWorkoutsForOverride: [ProgramWorkoutOutline] = []

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
                availableWorkoutsForOverride = []
                return
            }
            availableWorkoutsForOverride = try ProgramOutlineRepository(modelContext: modelContext)
                .activeProgramOutline()?.workouts ?? []
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
                    resolved = .workoutAlreadyFinished(workoutId: workoutId, title: title)
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

    /// Forces today onto `value` and cascades every later scheduled day forward by one — the same mechanic as the
    /// Program tab's schedule picker, surfaced here for the “missed a day, resume today” flow: forcing today to the
    /// workout you actually want to do now pushes the rest of the rotation to keep its order intact, so you don't
    /// have to fix each day by hand.
    func forceTodaysSchedule(to value: ProgramDaySchedulePickerValue) {
        let calendar = Calendar.current
        let today = CalendarDate(from: dateProvider.now, calendar: calendar)
        do {
            try ProgramRepository(modelContext: modelContext).setScheduleDayShiftingFollowing(
                from: today,
                value: value,
                calendar: calendar
            )
            refresh()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Puts today's finished session back in progress (it leaves History until finished again).
    /// Returns false if the reopen failed, so the caller doesn't navigate to a fresh empty session.
    func reopenFinishedWorkout(workoutId: UUID) -> Bool {
        let today = CalendarDate(from: dateProvider.now, calendar: Calendar.current)
        do {
            try WorkoutSessionRepository(modelContext: modelContext).reopenCompletedSession(templateId: workoutId, day: today)
            refresh()
            return true
        } catch {
            loadError = error.localizedDescription
            return false
        }
    }

    var headline: String {
        guard let status else { return "Loading…" }
        switch status {
        case .noProgram: return "No program"
        case .dayNotScheduled: return "Not on schedule"
        case .restDay: return "Rest day"
        case .workoutDay(_, let title): return title
        case .workoutInProgress(_, let title): return title
        case .workoutAlreadyFinished(_, let title): return title
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
        case .workoutAlreadyFinished: return "You’ve already logged this session today. Reopen it if you finished by mistake."
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

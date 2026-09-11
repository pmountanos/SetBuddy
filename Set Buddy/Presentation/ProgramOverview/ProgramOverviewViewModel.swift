//
//  ProgramOverviewViewModel.swift
//  Set Buddy
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class ProgramOverviewViewModel {
    private let modelContext: ModelContext

    var outline: ProgramOutline?
    var scheduleRows: [ProgramScheduleDayRow] = []
    var errorMessage: String?

    /// Bound to the program header; committed on submit / defocus flows via `commitProgramName()`.
    var programNameDraft: String = ""

    /// Shown when there is no program yet (create without import).
    var newProgramNameDraft: String = "My program"

    /// Name/exercises/sets editing for one workout template's sheet. `var` (never reassigned after init) so SwiftUI's
    /// `@Bindable` dynamic member lookup can form a binding straight through to e.g. `$viewModel.workoutEditor.presented`.
    var workoutEditor: WorkoutTemplateEditorViewModel

    var exerciseNoteSheetPresented = false
    var exerciseNoteSheetTitle = ""
    var exerciseNoteSheetBody = ""
    private(set) var exerciseNoteExerciseId: UUID?

    var deleteWorkoutConfirmationPresented = false
    var workoutPendingDeletionId: UUID?
    var workoutPendingDeletionName: String = ""

    var startOverConfirmationPresented = false

    /// Mirrored from Settings → Program (upcoming schedule list length); updated in `refresh()`.
    var schedulePreviewDayCount: Int = 14

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.workoutEditor = WorkoutTemplateEditorViewModel(modelContext: modelContext)
    }

    func refresh() {
        errorMessage = nil
        do {
            try ProgramRepository.addExerciseTemplatesIfMissing(modelContext: modelContext)
            try ProgramRepository(modelContext: modelContext).ensureForwardScheduleFilled()
            let repo = ProgramOutlineRepository(modelContext: modelContext)
            outline = try repo.activeProgramOutline()
            programNameDraft = outline?.programName ?? ""
            let calendar = Calendar.current
            let limit = ProgramSchedulePreviewDaysSetting.load()
            schedulePreviewDayCount = limit
            scheduleRows = try repo.upcomingScheduleRows(limit: limit, calendar: calendar)
        } catch {
            errorMessage = error.localizedDescription
            outline = nil
            scheduleRows = []
            programNameDraft = ""
        }
    }

    func commitProgramName() {
        let repo = ProgramRepository(modelContext: modelContext)
        try? repo.renameProgram(to: programNameDraft)
        refresh()
    }

    func createProgramFromDraft() {
        let repo = ProgramRepository(modelContext: modelContext)
        do {
            _ = try repo.createFirstProgram(name: newProgramNameDraft)
            newProgramNameDraft = "My program"
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestStartOver() {
        startOverConfirmationPresented = true
    }

    func cancelStartOver() {
        startOverConfirmationPresented = false
    }

    /// Same safety as replacing via import: clears in-progress logging, keeps finished sessions in History, inserts a new starter program. `clearActiveWorkoutSelection` should clear `AppRouter.selectedWorkoutId`.
    func confirmStartOver(clearActiveWorkoutSelection: () -> Void) {
        workoutEditor.presented = false
        exerciseNoteSheetPresented = false
        deleteWorkoutConfirmationPresented = false
        workoutPendingDeletionId = nil
        workoutPendingDeletionName = ""

        let trimmed = programNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameForNewProgram = trimmed.isEmpty ? "My program" : trimmed

        do {
            let repo = ProgramRepository(modelContext: modelContext)
            _ = try repo.startOverFreshProgram(name: nameForNewProgram)
            clearActiveWorkoutSelection()
            startOverConfirmationPresented = false
            newProgramNameDraft = "My program"
            refresh()
            DailyNotificationScheduler.requestReschedule(modelContext: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setSchedulePickerValue(_ value: ProgramDaySchedulePickerValue, for date: CalendarDate) {
        let repo = ProgramRepository(modelContext: modelContext)
        try? repo.setScheduleDayShiftingFollowing(from: date, value: value, calendar: Calendar.current)
        refresh()
    }

    /// Inserts a rest day on `date` and pushes that day’s plan (and all later days through the program horizon) forward by one calendar day.
    func insertRestDay(at date: CalendarDate) {
        do {
            try ProgramRepository(modelContext: modelContext).insertRestDayShiftingFollowing(from: date, calendar: Calendar.current)
            refresh()
            DailyNotificationScheduler.requestReschedule(modelContext: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addWorkout() {
        do {
            _ = try ProgramRepository(modelContext: modelContext).addWorkout()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestDeleteWorkout(id: UUID, name: String) {
        workoutPendingDeletionId = id
        workoutPendingDeletionName = name
        deleteWorkoutConfirmationPresented = true
    }

    func confirmDeleteWorkout() {
        guard let id = workoutPendingDeletionId else { return }
        try? ProgramRepository(modelContext: modelContext).deleteWorkout(id: id)
        workoutPendingDeletionId = nil
        workoutPendingDeletionName = ""
        deleteWorkoutConfirmationPresented = false
        refresh()
    }

    func cancelDeleteWorkout() {
        workoutPendingDeletionId = nil
        workoutPendingDeletionName = ""
        deleteWorkoutConfirmationPresented = false
    }

    /// Called when the delete confirmation dialog is dismissed (outside tap or after action).
    func onDeleteWorkoutDialogDismissed() {
        if workoutPendingDeletionId != nil {
            workoutPendingDeletionId = nil
            workoutPendingDeletionName = ""
        }
    }

    /// Opens the template editor for this workout (exercises, names, sets, per-side).
    func presentWorkoutEditor(workoutId: UUID) {
        guard let outline, let workout = outline.workouts.first(where: { $0.id == workoutId }) else { return }
        workoutEditor.present(workout: workout)
    }

    /// Called when the template editor sheet is dismissed (Done or swipe): persists the title and refreshes the outline.
    func onWorkoutEditorDismissed() {
        workoutEditor.persistTitleAndReset()
        refresh()
    }

    func presentExerciseNote(exercise: ProgramExerciseOutline) {
        exerciseNoteExerciseId = exercise.id
        exerciseNoteSheetTitle = exercise.name
        exerciseNoteSheetBody = exercise.note ?? ""
        exerciseNoteSheetPresented = true
    }

    func saveExerciseNote(_ text: String) {
        guard let id = exerciseNoteExerciseId else { return }
        try? ProgramRepository(modelContext: modelContext).setExerciseNote(id: id, note: text)
        exerciseNoteExerciseId = nil
        refresh()
    }

    func onExerciseNoteEditorDismissed() {
        exerciseNoteExerciseId = nil
    }
}

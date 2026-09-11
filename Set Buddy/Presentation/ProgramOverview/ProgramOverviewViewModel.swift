//
//  ProgramOverviewViewModel.swift
//  Set Buddy
//

import Foundation
import SwiftData
import SwiftUI

/// One row in the workout template editor sheet (bindings update persisted exercises).
struct WorkoutEditorExerciseRow: Identifiable, Hashable {
    let id: UUID
    var name: String
    var setCount: Int
    var repsArePerSide: Bool
}

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

    var workoutEditorPresented = false
    var workoutEditorWorkoutId: UUID?
    /// Editable workout template title while the sheet is open.
    var workoutEditorWorkoutName: String = ""
    var workoutEditorRows: [WorkoutEditorExerciseRow] = []

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
        workoutEditorPresented = false
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
            Task {
                await DailyNotificationScheduler.shared.reschedule(modelContext: modelContext)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func schedulePickerValue(for row: ProgramScheduleDayRow) -> ProgramDaySchedulePickerValue {
        if row.isRestDay { return .rest }
        if let id = row.workoutTemplateId { return .workout(id) }
        return .rest
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
            Task {
                await DailyNotificationScheduler.shared.reschedule(modelContext: modelContext)
            }
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
        guard let outline else { return }
        guard let workout = outline.workouts.first(where: { $0.id == workoutId }) else { return }
        workoutEditorWorkoutId = workoutId
        workoutEditorWorkoutName = workout.name
        workoutEditorRows = workout.exercises.map {
            WorkoutEditorExerciseRow(
                id: $0.id,
                name: $0.name,
                setCount: max(1, min(20, $0.setCount)),
                repsArePerSide: $0.repsArePerSide
            )
        }
        workoutEditorPresented = true
    }

    func persistWorkoutEditorTitle() {
        guard let id = workoutEditorWorkoutId else { return }
        try? ProgramRepository(modelContext: modelContext).renameWorkout(id: id, to: workoutEditorWorkoutName)
        refresh()
    }

    func persistExerciseName(exerciseId: UUID, name: String) {
        try? ProgramRepository(modelContext: modelContext).setExerciseName(id: exerciseId, name: name)
    }

    func persistExerciseSetCount(exerciseId: UUID, count: Int) {
        try? ProgramRepository(modelContext: modelContext).setExerciseSetCount(id: exerciseId, setCount: count)
    }

    func persistExerciseRepsPerSide(exerciseId: UUID, value: Bool) {
        try? ProgramRepository(modelContext: modelContext).setExerciseRepsPerSide(id: exerciseId, value: value)
    }

    func addExerciseToOpenWorkout() {
        guard let wid = workoutEditorWorkoutId else { return }
        try? ProgramRepository(modelContext: modelContext).addExercise(toWorkout: wid)
        reloadWorkoutEditorRowsFromStore()
    }

    func deleteExercises(at offsets: IndexSet) {
        for index in offsets {
            guard workoutEditorRows.indices.contains(index) else { continue }
            let id = workoutEditorRows[index].id
            try? ProgramRepository(modelContext: modelContext).deleteExercise(id: id)
        }
        reloadWorkoutEditorRowsFromStore()
    }

    func moveExercises(from source: IndexSet, to destination: Int) {
        guard let wid = workoutEditorWorkoutId else { return }
        workoutEditorRows.move(fromOffsets: source, toOffset: destination)
        let ids = workoutEditorRows.map(\.id)
        try? ProgramRepository(modelContext: modelContext).reorderExercises(inWorkout: wid, orderedExerciseIds: ids)
        reloadWorkoutEditorRowsFromStore()
    }

    private func reloadWorkoutEditorRowsFromStore() {
        guard let wid = workoutEditorWorkoutId else { return }
        let repo = ProgramOutlineRepository(modelContext: modelContext)
        guard let fresh = try? repo.activeProgramOutline(),
              let workout = fresh.workouts.first(where: { $0.id == wid })
        else { return }
        workoutEditorRows = workout.exercises.map {
            WorkoutEditorExerciseRow(
                id: $0.id,
                name: $0.name,
                setCount: max(1, min(20, $0.setCount)),
                repsArePerSide: $0.repsArePerSide
            )
        }
    }

    func onWorkoutEditorDismissed() {
        persistWorkoutEditorTitle()
        workoutEditorTitleReset()
        refresh()
    }

    private func workoutEditorTitleReset() {
        workoutEditorWorkoutId = nil
        workoutEditorWorkoutName = ""
        workoutEditorRows = []
    }

    func presentExerciseNote(exercise: ProgramExerciseOutline) {
        exerciseNoteExerciseId = exercise.id
        exerciseNoteSheetTitle = exercise.name
        exerciseNoteSheetBody = exercise.note ?? ""
        exerciseNoteSheetPresented = true
    }

    func saveExerciseNote(_ text: String) {
        guard let id = exerciseNoteExerciseId else { return }
        let all = (try? modelContext.fetch(FetchDescriptor<PersistedExercise>())) ?? []
        guard let ex = all.first(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        ex.note = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
        exerciseNoteExerciseId = nil
        refresh()
    }

    func onExerciseNoteEditorDismissed() {
        exerciseNoteExerciseId = nil
    }
}

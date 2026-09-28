//
//  WorkoutTemplateEditorViewModel.swift
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
    var kind: ExerciseKind
}

/// Editing state for one workout template's sheet: name, exercises (add/rename/reorder/delete), sets, per-side.
/// Owned by `ProgramOverviewViewModel`; split out because it's a self-contained editing subsystem distinct from
/// the program-level schedule/CRUD concerns the parent otherwise handles.
@MainActor
@Observable
final class WorkoutTemplateEditorViewModel {
    private let modelContext: ModelContext

    var presented = false
    private(set) var workoutId: UUID?
    /// Editable workout template title while the sheet is open.
    var workoutName: String = ""
    var rows: [WorkoutEditorExerciseRow] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func present(workout: ProgramWorkoutOutline) {
        workoutId = workout.id
        workoutName = workout.name
        rows = Self.rows(from: workout.exercises)
        presented = true
    }

    /// Called on sheet dismiss (Done or swipe): persists the title, then clears editor state.
    func persistTitleAndReset() {
        if let id = workoutId {
            try? ProgramRepository(modelContext: modelContext).renameWorkout(id: id, to: workoutName)
        }
        workoutId = nil
        workoutName = ""
        rows = []
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

    func persistExerciseKind(exerciseId: UUID, kind: ExerciseKind) {
        try? ProgramRepository(modelContext: modelContext).setExerciseKind(id: exerciseId, kind: kind)
    }

    func addExercise() {
        guard let wid = workoutId else { return }
        try? ProgramRepository(modelContext: modelContext).addExercise(toWorkout: wid)
        reloadRowsFromStore()
    }

    func deleteExercises(at offsets: IndexSet) {
        for index in offsets {
            guard rows.indices.contains(index) else { continue }
            try? ProgramRepository(modelContext: modelContext).deleteExercise(id: rows[index].id)
        }
        reloadRowsFromStore()
    }

    func moveExercises(from source: IndexSet, to destination: Int) {
        guard let wid = workoutId else { return }
        rows.move(fromOffsets: source, toOffset: destination)
        let ids = rows.map(\.id)
        try? ProgramRepository(modelContext: modelContext).reorderExercises(inWorkout: wid, orderedExerciseIds: ids)
        reloadRowsFromStore()
    }

    private func reloadRowsFromStore() {
        guard let wid = workoutId else { return }
        let repo = ProgramOutlineRepository(modelContext: modelContext)
        guard let fresh = try? repo.activeProgramOutline(),
              let workout = fresh.workouts.first(where: { $0.id == wid })
        else { return }
        rows = Self.rows(from: workout.exercises)
    }

    private static func rows(from exercises: [ProgramExerciseOutline]) -> [WorkoutEditorExerciseRow] {
        exercises.map {
            WorkoutEditorExerciseRow(
                id: $0.id,
                name: $0.name,
                setCount: max(1, min(20, $0.setCount)),
                repsArePerSide: $0.repsArePerSide,
                kind: $0.kind
            )
        }
    }
}

//
//  WorkoutTemplateEditorSheet.swift
//  Set Buddy
//

import SwiftUI

/// Edit one workout template: name, exercise names, set counts, per-side, order, add/remove exercises.
struct WorkoutTemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ProgramOverviewViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Workout name", text: $viewModel.workoutEditorWorkoutName)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Shown on Today and in the log. Saved when you tap Done.")
                        .font(.footnote)
                }

                Section {
                    Text(
                        "Per side: each rep is one limb (e.g. dumbbell). Volume doubles to count both sides."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                ForEach($viewModel.workoutEditorRows) { $row in
                    Section {
                        TextField("Exercise name", text: $row.name)
                            .onChange(of: row.name) { _, newValue in
                                viewModel.persistExerciseName(exerciseId: row.id, name: newValue)
                            }
                        Stepper("Sets to log: \(row.setCount)", value: $row.setCount, in: 1 ... 20)
                            .onChange(of: row.setCount) { _, newValue in
                                viewModel.persistExerciseSetCount(exerciseId: row.id, count: newValue)
                            }
                        Toggle("Per side — volume ×2", isOn: $row.repsArePerSide)
                            .accessibilityIdentifier("workoutEditorPerSideToggle-\(row.id.uuidString)")
                            .onChange(of: row.repsArePerSide) { _, newValue in
                                viewModel.persistExerciseRepsPerSide(exerciseId: row.id, value: newValue)
                            }
                    }
                }
                .onDelete(perform: viewModel.deleteExercises)
                .onMove(perform: viewModel.moveExercises)
            }
            .navigationTitle("Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("workoutTemplateEditorDone")
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        viewModel.addExerciseToOpenWorkout()
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle")
                    }
                }
            }
        }
    }
}

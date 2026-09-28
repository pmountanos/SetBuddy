//
//  WorkoutTemplateEditorSheet.swift
//  Set Buddy
//

import SwiftUI

/// Edit one workout template: name, exercise names, set counts, per-side, order, add/remove exercises.
struct WorkoutTemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: WorkoutTemplateEditorViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Workout name", text: $viewModel.workoutName)
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

                ForEach($viewModel.rows) { $row in
                    Section {
                        TextField("Exercise name", text: $row.name)
                            .onChange(of: row.name) { _, newValue in
                                viewModel.persistExerciseName(exerciseId: row.id, name: newValue)
                            }
                        Picker("Type", selection: $row.kind) {
                            Text("Strength").tag(ExerciseKind.strength)
                            Text("Cardio").tag(ExerciseKind.cardio)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("workoutEditorKindPicker-\(row.id.uuidString)")
                        .onChange(of: row.kind) { _, newValue in
                            viewModel.persistExerciseKind(exerciseId: row.id, kind: newValue)
                        }
                        Stepper("Sets to log: \(row.setCount)", value: $row.setCount, in: 1 ... 20)
                            .onChange(of: row.setCount) { _, newValue in
                                viewModel.persistExerciseSetCount(exerciseId: row.id, count: newValue)
                            }
                        if row.kind == .strength {
                            Toggle("Per side — volume ×2", isOn: $row.repsArePerSide)
                                .accessibilityIdentifier("workoutEditorPerSideToggle-\(row.id.uuidString)")
                                .onChange(of: row.repsArePerSide) { _, newValue in
                                    viewModel.persistExerciseRepsPerSide(exerciseId: row.id, value: newValue)
                                }
                        } else {
                            Text("Cardio sets log minutes and max heart rate instead of weight/reps.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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
                        viewModel.addExercise()
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle")
                    }
                }
            }
        }
    }
}

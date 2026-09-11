//
//  ProgramOverviewScreen.swift
//  Set Buddy
//

import SwiftData
import SwiftUI

struct ProgramOverviewScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @State private var viewModel: ProgramOverviewViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    ProgramOverviewContent(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Program")
            .task {
                if viewModel == nil {
                    viewModel = ProgramOverviewViewModel(modelContext: modelContext)
                }
                viewModel?.refresh()
            }
            .refreshable {
                viewModel?.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .programSchedulePreviewDaysDidChange)) { _ in
                viewModel?.refresh()
            }
            .toolbar {
                if viewModel?.outline != nil {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            viewModel?.requestStartOver()
                        } label: {
                            Label("Start over", systemImage: "arrow.counterclockwise")
                        }
                        .accessibilityIdentifier("programStartOverButton")
                        Button {
                            viewModel?.addWorkout()
                        } label: {
                            Label("Add workout", systemImage: "plus")
                        }
                        .accessibilityIdentifier("programAddWorkoutButton")
                    }
                }
            }
            .confirmationDialog(
                "Start over?",
                isPresented: Binding(
                    get: { viewModel?.startOverConfirmationPresented ?? false },
                    set: { newVal in
                        viewModel?.startOverConfirmationPresented = newVal
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Start over", role: .destructive) {
                    viewModel?.confirmStartOver {
                        router.selectedWorkoutId = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    viewModel?.cancelStartOver()
                }
            } message: {
                Text(
                    "Your current program and schedule are removed and replaced with a fresh starter. Completed workouts stay in History; any workout in progress is cleared. The new program uses the name in the title field above (or “My program” if it’s empty)."
                )
            }
            .confirmationDialog(
                "Delete workout?",
                isPresented: Binding(
                    get: { viewModel?.deleteWorkoutConfirmationPresented ?? false },
                    set: { newVal in
                        viewModel?.deleteWorkoutConfirmationPresented = newVal
                        if !newVal {
                            viewModel?.onDeleteWorkoutDialogDismissed()
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button(
                    "Delete “\(viewModel?.workoutPendingDeletionName ?? "workout")”",
                    role: .destructive
                ) {
                    viewModel?.confirmDeleteWorkout()
                }
                Button("Cancel", role: .cancel) {
                    viewModel?.cancelDeleteWorkout()
                }
            } message: {
                Text("Scheduled days that used this workout become rest days.")
            }
        }
    }
}

private struct ProgramOverviewContent: View {
    @Bindable var viewModel: ProgramOverviewViewModel

    var body: some View {
        Group {
            if let err = viewModel.errorMessage {
                ContentUnavailableView("Couldn’t load", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if let outline = viewModel.outline {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Program name", text: $viewModel.programNameDraft)
                                .font(.title2.weight(.semibold))
                                .textInputAutocapitalization(.words)
                                .onSubmit {
                                    viewModel.commitProgramName()
                                }
                            Text(
                                "Edit the program name, schedule, and workouts here — same fields as a spreadsheet import. Use Start over in the toolbar or Import in Settings to replace the program; finished workouts stay in History, in‑progress logging is cleared."
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)
                    }
                    Section {
                        if viewModel.scheduleRows.isEmpty {
                            Text("No upcoming days on your calendar yet. Pull to refresh, or check your device date.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.scheduleRows) { row in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(row.dateLabel)
                                        .frame(minWidth: 88, alignment: .leading)
                                    Menu {
                                        Button("Rest") {
                                            viewModel.setSchedulePickerValue(.rest, for: row.date)
                                        }
                                        ForEach(outline.workouts) { w in
                                            Button(w.name) {
                                                viewModel.setSchedulePickerValue(.workout(w.id), for: row.date)
                                            }
                                        }
                                        Divider()
                                        Button("Add a rest day") {
                                            viewModel.insertRestDay(at: row.date)
                                        }
                                    } label: {
                                        Text(row.isRestDay ? "Rest" : row.subtitle)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    } header: {
                        Text("Upcoming schedule")
                    } footer: {
                        Text(
                            "Next \(viewModel.schedulePreviewDayCount) days from today (change length in Settings → Program). Choosing Rest or a workout pushes that day’s previous assignment and everything after it forward by one day so the sequence stays aligned (same cascade as Add a rest day). Tap a workout name below for exercises, sets, and notes."
                        )
                        .font(.footnote)
                    }
                    ForEach(outline.workouts) { workout in
                        Section {
                            if workout.exercises.isEmpty {
                                Text("No exercises yet")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(workout.exercises) { exercise in
                                    Button {
                                        viewModel.presentExerciseNote(exercise: exercise)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                Text(exercise.name)
                                                    .foregroundStyle(.primary)
                                                Spacer(minLength: 0)
                                                if exercise.hasNonEmptyNote {
                                                    Image(systemName: "note.text")
                                                        .font(.subheadline.weight(.medium))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            HStack(spacing: 6) {
                                                Text("\(exercise.setCount) sets")
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                                if exercise.repsArePerSide {
                                                    Text("· Per side ×2")
                                                        .font(.caption2)
                                                        .foregroundStyle(.tertiary)
                                                }
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Opens note editor for this exercise")
                                }
                            }
                        } header: {
                            Button {
                                viewModel.presentWorkoutEditor(workoutId: workout.id)
                            } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(workout.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 8)
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Edits this workout template, including per-side reps")
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.requestDeleteWorkout(id: workout.id, name: workout.name)
                                } label: {
                                    Label("Delete workout", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .sheet(isPresented: $viewModel.workoutEditorPresented, onDismiss: {
                    // Persist workout title and clear editor state after dismiss (Done or swipe).
                    viewModel.onWorkoutEditorDismissed()
                }) {
                    WorkoutTemplateEditorSheet(viewModel: viewModel)
                }
                .sheet(isPresented: $viewModel.exerciseNoteSheetPresented, onDismiss: {
                    viewModel.onExerciseNoteEditorDismissed()
                }) {
                    ExerciseNoteEditorSheet(
                        title: viewModel.exerciseNoteSheetTitle,
                        initialNote: viewModel.exerciseNoteSheetBody,
                        onSave: { viewModel.saveExerciseNote($0) }
                    )
                }
            } else {
                ContentUnavailableView {
                    Label("No program yet", systemImage: "calendar")
                } description: {
                    Text("Create one here (same fields as a spreadsheet import), or import a workbook from Settings.")
                } actions: {
                    VStack(alignment: .center, spacing: 12) {
                        TextField("Program name", text: $viewModel.newProgramNameDraft)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("programNewProgramNameField")
                        Button {
                            viewModel.createProgramFromDraft()
                        } label: {
                            Text("Create program")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("programCreateProgramButton")
                    }
                    .frame(maxWidth: 320)
                    if let err = viewModel.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }
}

#Preview {
    let schema = Schema([
        PersistedProgram.self,
        PersistedWorkout.self,
        PersistedScheduleEntry.self,
        PersistedExercise.self,
        PersistedWorkoutSession.self,
        PersistedLoggedSet.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    let context = container.mainContext
    try? ProgramRepository.seedIfNeeded(modelContext: context)
    try? ProgramRepository.addExerciseTemplatesIfMissing(modelContext: context)
    return ProgramOverviewScreen()
        .modelContainer(container)
        .environment(AppRouter())
}

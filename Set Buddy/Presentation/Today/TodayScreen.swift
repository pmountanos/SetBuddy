//
//  TodayScreen.swift
//  Set Buddy
//

import SwiftUI
import SwiftData

struct TodayScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @State private var viewModel: TodayViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    TodayStatusContent(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Today")
            .task {
                if viewModel == nil {
                    viewModel = TodayViewModel(modelContext: modelContext)
                }
                viewModel?.refresh()
            }
            .onChange(of: router.selectedTab) { _, tab in
                if tab == .today {
                    viewModel?.refresh()
                }
            }
            .refreshable {
                viewModel?.refresh()
            }
        }
    }
}

private struct TodayStatusContent: View {
    @Bindable var viewModel: TodayViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        ContentUnavailableView {
            Label(viewModel.headline, systemImage: viewModel.symbolName)
        } description: {
            VStack(spacing: 12) {
                Text(viewModel.detail)
                if case .noProgram = viewModel.status {
                    Button {
                        router.selectedTab = .program
                    } label: {
                        Text("Create program")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("todayGoToProgramButton")
                }
                if case .workoutDay(let workoutId, let title) = viewModel.status {
                    Button {
                        router.openWorkoutLogging(workoutId: workoutId)
                    } label: {
                        Text("Start \(title)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("todayStartWorkoutButton")
                }
                if case .workoutInProgress(let workoutId, let title) = viewModel.status {
                    Button {
                        router.openWorkoutLogging(workoutId: workoutId)
                    } label: {
                        Text("Continue \(title)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("todayContinueWorkoutButton")
                }
                if case .workoutAlreadyFinished(let workoutId, let title) = viewModel.status {
                    Button {
                        if viewModel.reopenFinishedWorkout(workoutId: workoutId) {
                            router.openWorkoutLogging(workoutId: workoutId)
                        }
                    } label: {
                        Text("Reopen \(title)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("todayReopenWorkoutButton")
                }
                if showChangePlanMenu {
                    Menu {
                        Button("Rest") {
                            viewModel.forceTodaysSchedule(to: .rest)
                        }
                        ForEach(viewModel.availableWorkoutsForOverride) { workout in
                            Button(workout.name) {
                                viewModel.forceTodaysSchedule(to: .workout(workout.id))
                            }
                        }
                    } label: {
                        Text("Change today’s plan")
                            .font(.subheadline)
                    }
                    .accessibilityIdentifier("todayChangePlanMenu")
                }
                if let err = viewModel.loadError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: 360)
        }
    }

    /// Hidden until there's a program to pick from — lets you realign the schedule to what you're actually doing
    /// today (e.g. after missing a day) instead of leaving the calendar out of sync. Same cascade as the Program
    /// tab's schedule picker: everything after today shifts to keep the workout rotation's order intact.
    private var showChangePlanMenu: Bool {
        if case .noProgram = viewModel.status { return false }
        return viewModel.status != nil
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
    return TodayScreen()
        .modelContainer(container)
        .environment(AppRouter())
}

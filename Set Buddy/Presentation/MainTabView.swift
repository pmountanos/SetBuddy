//
//  MainTabView.swift
//  Set Buddy
//

import SwiftData
import SwiftUI

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var router = AppRouter()

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            TodayScreen()
                .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.systemImage) }
                .tag(AppTab.today)

            WorkoutLoggingScreen()
                .tabItem { Label(AppTab.workout.title, systemImage: AppTab.workout.systemImage) }
                .tag(AppTab.workout)

            ProgramOverviewScreen()
                .tabItem { Label(AppTab.program.title, systemImage: AppTab.program.systemImage) }
                .tag(AppTab.program)

            HistoryScreen()
                .tabItem { Label(AppTab.history.title, systemImage: AppTab.history.systemImage) }
                .tag(AppTab.history)

            SettingsScreen()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                .tag(AppTab.settings)
        }
        .environment(router)
        .task {
            if UITestLaunch.isUITesting {
                try? ProgramRepository.seedIfNeeded(modelContext: modelContext)
            }
            try? ProgramRepository.addExerciseTemplatesIfMissing(modelContext: modelContext)
            try? ProgramRepository.migrateLegacyImportedProgramTitles(modelContext: modelContext)
            try? ProgramRepository(modelContext: modelContext).ensureForwardScheduleFilled()
            if !UITestLaunch.isUITesting {
                await NotificationPermission.requestIfNeeded()
            }
            DailyNotificationScheduler.requestReschedule(modelContext: modelContext)
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
    MainTabView()
        .modelContainer(container)
}

//
//  Set_BuddyApp.swift
//  Set Buddy
//
//  Created by PETE MOUNTANOS on 3/22/26.
//

import SwiftData
import SwiftUI

@main
struct Set_BuddyApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PersistedProgram.self,
            PersistedWorkout.self,
            PersistedScheduleEntry.self,
            PersistedExercise.self,
            PersistedWorkoutSession.self,
            PersistedLoggedSet.self,
        ])
        // UI tests pass `-uiTesting` for a fresh in-memory store each launch (deterministic seed + schedule).
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: UITestLaunch.isUITesting)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}

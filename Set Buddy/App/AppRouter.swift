//
//  AppRouter.swift
//  Set Buddy
//

import Foundation
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case workout
    case program
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .workout: "Workout"
        case .program: "Program"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max.fill"
        case .workout: "figure.strengthtraining.traditional"
        case .program: "calendar"
        case .history: "chart.bar.fill"
        case .settings: "gearshape.fill"
        }
    }
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var selectedWorkoutId: UUID?

    func openWorkoutLogging(workoutId: UUID) {
        selectedWorkoutId = workoutId
        selectedTab = .workout
    }
}

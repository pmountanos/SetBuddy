//
//  HistoryScreen.swift
//  Set Buddy
//

import SwiftData
import SwiftUI

struct HistoryScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: HistoryViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    HistoryListContent(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("History")
            .task {
                if viewModel == nil {
                    viewModel = HistoryViewModel(modelContext: modelContext)
                }
                viewModel?.refresh()
            }
            .refreshable {
                viewModel?.refresh()
            }
        }
    }
}

private struct HistoryListContent: View {
    private static let volumeFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    @Bindable var viewModel: HistoryViewModel

    var body: some View {
        Group {
            if let err = viewModel.errorMessage {
                ContentUnavailableView("Couldn’t load", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if viewModel.rows.isEmpty {
                ContentUnavailableView(
                    "No completed workouts",
                    systemImage: "chart.bar",
                    description: Text("Finish a session from the Workout tab to see volume here.")
                )
            } else {
                List(viewModel.rows) { row in
                    NavigationLink(value: row.id) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.workoutTitle)
                                    .font(.headline)
                                Text(row.completedAt, style: .date)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Volume: \(Self.formatVolume(row.volume))")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                            }
                            Spacer(minLength: 0)
                            if row.hasSessionNote {
                                Image(systemName: "note.text")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Has workout note")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationDestination(for: UUID.self) { sessionId in
                    HistorySessionDetailView(sessionId: sessionId)
                }
            }
        }
    }

    private static func formatVolume(_ v: Double) -> String {
        volumeFormatter.string(from: NSNumber(value: v)) ?? "\(Int(v))"
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
    return HistoryScreen()
        .modelContainer(container)
}

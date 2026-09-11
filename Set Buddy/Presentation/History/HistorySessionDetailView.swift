//
//  HistorySessionDetailView.swift
//  Set Buddy
//

import SwiftData
import SwiftUI

struct HistorySessionDetailView: View {
    let sessionId: UUID
    @Environment(\.modelContext) private var modelContext

    @State private var detail: HistorySessionDetail?
    @State private var loadError: String?
    @State private var workoutNoteEditorPresented = false
    @State private var workoutNoteDraft = ""

    private static let volumeFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        Group {
            if let detail {
                List {
                    Section {
                        LabeledContent("Completed") {
                            Text(detail.completedAt, style: .date)
                        }
                        if let schedule = detail.scheduleDayLabel {
                            LabeledContent("Scheduled day", value: schedule)
                        }
                        LabeledContent("Total volume", value: Self.formatVolume(detail.totalVolume))
                    }

                    Section {
                        Button {
                            workoutNoteDraft = detail.sessionNote ?? ""
                            workoutNoteEditorPresented = true
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Workout note")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(workoutNoteRowBody(for: detail))
                                        .font(.body)
                                        .foregroundStyle(workoutNoteRowIsEmpty(detail) ? .tertiary : .primary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Image(systemName: "note.text")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("historySessionNoteRow")
                    }

                    ForEach(detail.exercises) { exercise in
                        Section {
                            ForEach(exercise.sets) { line in
                                HStack(alignment: .firstTextBaseline) {
                                    Text("Set \(line.setNumber)")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(Int(line.weight)) kg × \(line.reps)\(line.repsArePerSide ? " /side" : "")")
                                            .font(.body.monospacedDigit())
                                        if line.repsArePerSide {
                                            Text("Volume ×2 (both sides)")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(exercise.name)
                                Spacer(minLength: 8)
                                Text(Self.formatVolume(exercise.volume))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .sheet(isPresented: $workoutNoteEditorPresented) {
                    ExerciseNoteEditorSheet(
                        title: "Workout note",
                        initialNote: workoutNoteDraft,
                        onSave: { saveWorkoutNote($0) }
                    )
                }
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn’t open workout",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(detail?.workoutTitle ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sessionId) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        loadError = nil
        detail = nil
        do {
            if let d = try HistoryRepository(modelContext: modelContext).sessionDetail(sessionId: sessionId) {
                detail = d
            } else {
                loadError = "This session is no longer in your history."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func saveWorkoutNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor = FetchDescriptor<PersistedWorkoutSession>()
        descriptor.fetchLimit = 1
        descriptor.predicate = #Predicate { (s: PersistedWorkoutSession) in
            s.id == sessionId
        }
        guard let session = try? modelContext.fetch(descriptor).first else { return }
        session.sessionNote = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
        Task { await load() }
    }

    private static func formatVolume(_ v: Double) -> String {
        volumeFormatter.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    }

    private func workoutNoteRowIsEmpty(_ detail: HistorySessionDetail) -> Bool {
        (detail.sessionNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    private func workoutNoteRowBody(for detail: HistorySessionDetail) -> String {
        let trimmed = detail.sessionNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Tap to add or edit" : trimmed
    }
}

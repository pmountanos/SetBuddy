//
//  WorkoutLoggingViewModel.swift
//  Set Buddy
//

import Foundation
import SwiftData

@MainActor
@Observable
final class WorkoutLoggingViewModel {
    struct ExerciseSection: Identifiable {
        let id: UUID
        let name: String
        /// True when a non-empty note exists (shows a hint in the header).
        let hasNote: Bool
        /// Reps are per side; session volume doubles for each set of this exercise.
        let repsArePerSide: Bool
        /// Strength (weight/reps) or cardio (minutes/max heart rate) — drives which fields the row shows.
        let kind: ExerciseKind
        var rows: [SetRow]
    }

    struct SetRow: Identifiable {
        let id: String
        let exerciseId: UUID
        let setIndex: Int
        let setNumber: Int
        /// Persisted values (zeros until the user enters data for this set).
        var weight: Double
        var reps: Int
        /// Cardio values (unused for strength rows).
        var cardioMinutes: Double
        var maxHeartRate: Int
        /// Last completed session values for this exercise/set — UI only until entered.
        var referenceWeight: Double
        var referenceReps: Int
        var referenceCardioMinutes: Double
        var referenceMaxHeartRate: Int
        /// True after the user has entered and committed data for this set (`PersistedLoggedSet.userEditedValues`).
        var isEntered: Bool
    }

    private let modelContext: ModelContext
    private let router: AppRouter
    private let dateProvider: DateProviding

    private var session: PersistedWorkoutSession?
    private var workout: PersistedWorkout?

    var workoutTitle: String?
    var sections: [ExerciseSection] = []
    var errorMessage: String?
    var isLoading = false

    var exerciseNoteSheetPresented = false
    var exerciseNoteSheetTitle = ""
    /// Empty means no note was saved for this exercise.
    var exerciseNoteSheetBody = ""
    private(set) var exerciseNoteExerciseId: UUID?

    var sessionNoteSheetPresented = false
    var sessionNoteSheetBody = ""
    /// Bumped when `sessionNote` changes so SwiftUI refreshes bindings that read from the session.
    private(set) var sessionNoteRefreshStamp = 0

    /// Sum of weight × reps for sets the user has entered this session (reference-only rows contribute 0).
    var sessionVolume: Double {
        guard let session else { return 0 }
        return session.loggedSets
            .filter(\.userEditedValues)
            .reduce(0) {
                $0 + VolumeCalculator.setVolume(weight: $1.weight, reps: $1.reps, repsArePerSide: $1.repsArePerSide)
            }
    }

    var sessionVolumeLabel: String {
        let v = sessionVolume
        if v >= 1000 {
            return NumberFormatter.localizedString(from: NSNumber(value: v), number: .decimal)
        }
        return "\(Int(v))"
    }

    /// True when the active session has a non-empty workout note.
    var hasWorkoutSessionNote: Bool {
        let t = session?.sessionNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !t.isEmpty
    }

    /// Short preview for the finish sheet (optional).
    var workoutSessionNotePreview: String {
        session?.sessionNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    init(modelContext: ModelContext, router: AppRouter, dateProvider: DateProviding = SystemDateProvider()) {
        self.modelContext = modelContext
        self.router = router
        self.dateProvider = dateProvider
    }

    func loadFromRouter() {
        errorMessage = nil
        guard let templateId = router.selectedWorkoutId else {
            workout = nil
            session = nil
            workoutTitle = nil
            sections = []
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try ProgramRepository.addExerciseTemplatesIfMissing(modelContext: modelContext)
            let sessionRepo = WorkoutSessionRepository(modelContext: modelContext)
            guard let w = try sessionRepo.workout(templateId: templateId) else {
                errorMessage = "Workout not found."
                workoutTitle = nil
                sections = []
                return
            }
            workout = w
            workoutTitle = w.name
            let calendar = Calendar.current
            let today = CalendarDate(from: dateProvider.now, calendar: calendar)
            let s = try sessionRepo.getOrCreateActiveSession(templateId: templateId, day: today, workout: w)
            session = s
            rebuildSections(workout: w, session: s)
        } catch {
            errorMessage = error.localizedDescription
            workoutTitle = nil
            sections = []
        }
    }

    private func rebuildSections(workout: PersistedWorkout, session: PersistedWorkoutSession) {
        let sessionRepo = WorkoutSessionRepository(modelContext: modelContext)
        let referenceValues = (try? sessionRepo.mostRecentLoggedValuesByExercise()) ?? [:]
        let ordered = workout.exercises.sorted { $0.sortOrder < $1.sortOrder }
        var result: [ExerciseSection] = []
        for exercise in ordered {
            var rows: [SetRow] = []
            for setIdx in 0 ..< exercise.setCount {
                let logged = session.loggedSets.first { $0.exerciseId == exercise.id && $0.setIndex == setIdx }
                let weight = logged?.weight ?? 0
                let reps = logged?.reps ?? 0
                let cardioMinutes = logged?.cardioMinutes ?? 0
                let maxHeartRate = logged?.maxHeartRate ?? 0
                let isEntered = logged?.userEditedValues ?? false
                let refMatch = referenceValues[exercise.id]?[setIdx]
                let referenceWeight = refMatch?.weight ?? 0
                let referenceReps = refMatch?.reps ?? 0
                let referenceCardioMinutes = refMatch?.cardioMinutes ?? 0
                let referenceMaxHeartRate = refMatch?.maxHeartRate ?? 0
                rows.append(
                    SetRow(
                        id: "\(exercise.id.uuidString)-\(setIdx)",
                        exerciseId: exercise.id,
                        setIndex: setIdx,
                        setNumber: setIdx + 1,
                        weight: weight,
                        reps: reps,
                        cardioMinutes: cardioMinutes,
                        maxHeartRate: maxHeartRate,
                        referenceWeight: referenceWeight,
                        referenceReps: referenceReps,
                        referenceCardioMinutes: referenceCardioMinutes,
                        referenceMaxHeartRate: referenceMaxHeartRate,
                        isEntered: isEntered
                    )
                )
            }
            let noteTrimmed = exercise.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasNote = !noteTrimmed.isEmpty
            result.append(
                ExerciseSection(
                    id: exercise.id,
                    name: exercise.name,
                    hasNote: hasNote,
                    repsArePerSide: exercise.repsArePerSide,
                    kind: exercise.kind,
                    rows: rows
                )
            )
        }
        sections = result
    }

    func presentExerciseNote(exerciseId: UUID) {
        guard let workout else { return }
        guard let ex = workout.exercises.first(where: { $0.id == exerciseId }) else { return }
        exerciseNoteExerciseId = exerciseId
        exerciseNoteSheetTitle = ex.name
        exerciseNoteSheetBody = ex.note ?? ""
        exerciseNoteSheetPresented = true
    }

    func saveExerciseNote(_ text: String) {
        guard let workout, let eid = exerciseNoteExerciseId else { return }
        try? ProgramRepository(modelContext: modelContext).setExerciseNote(id: eid, note: text)
        exerciseNoteExerciseId = nil
        if let session {
            rebuildSections(workout: workout, session: session)
        }
    }

    func onExerciseNoteEditorDismissed() {
        exerciseNoteExerciseId = nil
    }

    func presentSessionNoteEditor() {
        sessionNoteSheetBody = session?.sessionNote ?? ""
        sessionNoteSheetPresented = true
    }

    func saveSessionNote(_ text: String) {
        guard let session else { return }
        try? WorkoutSessionRepository(modelContext: modelContext).setSessionNote(session, note: text)
        sessionNoteRefreshStamp += 1
        sessionNoteSheetPresented = false
    }

    /// Parses both fields; updates the model only when `markUserEntry` is true (user changed something vs. reference / focus snapshot).
    func updateLoggedSet(exerciseId: UUID, setIndex: Int, weight: Double, reps: Int, markUserEntry: Bool) {
        guard markUserEntry, let session, let w = workout else { return }
        try? WorkoutSessionRepository(modelContext: modelContext).updateLoggedSet(
            session: session,
            exerciseId: exerciseId,
            setIndex: setIndex,
            weight: weight,
            reps: reps
        )
        rebuildSections(workout: w, session: session)
    }

    /// Cardio counterpart of `updateLoggedSet` — records minutes/max heart rate instead of weight/reps.
    func updateCardioLoggedSet(exerciseId: UUID, setIndex: Int, minutes: Double, maxHeartRate: Int, markUserEntry: Bool) {
        guard markUserEntry, let session, let w = workout else { return }
        try? WorkoutSessionRepository(modelContext: modelContext).updateCardioLoggedSet(
            session: session,
            exerciseId: exerciseId,
            setIndex: setIndex,
            minutes: minutes,
            maxHeartRate: maxHeartRate
        )
        rebuildSections(workout: w, session: session)
    }

    func completeWorkout() {
        guard let s = session else { return }
        try? WorkoutSessionRepository(modelContext: modelContext).completeSession(s, workoutTitle: workoutTitle ?? "Workout")
        router.selectedWorkoutId = nil
        workout = nil
        session = nil
        workoutTitle = nil
        sections = []
        DailyNotificationScheduler.requestReschedule(modelContext: modelContext)
    }
}

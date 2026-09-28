//
//  WorkoutLoggingScreen.swift
//  Set Buddy
//

import SwiftData
import SwiftUI
import UIKit

struct WorkoutLoggingScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @State private var viewModel: WorkoutLoggingViewModel?
    @State private var finishWorkoutSheetPresented = false
    @FocusState private var workoutFieldFocus: LoggingFieldFocus?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    WorkoutLoggingContent(viewModel: viewModel, fieldFocus: $workoutFieldFocus)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(viewModel?.workoutTitle ?? "Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel?.workoutTitle != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Finish") {
                            if let f = workoutFieldFocus {
                                postWorkoutFieldCommit(f)
                            }
                            workoutFieldFocus = nil
                            resignFirstResponderGlobally()
                            finishWorkoutSheetPresented = true
                        }
                        .accessibilityIdentifier("workoutLogFinishButton")
                    }
                }
            }
            .sheet(isPresented: $finishWorkoutSheetPresented) {
                if let vm = viewModel {
                    FinishWorkoutSheet(
                        viewModel: vm,
                        onFinish: {
                            vm.completeWorkout()
                            finishWorkoutSheetPresented = false
                        },
                        onCancel: {
                            finishWorkoutSheetPresented = false
                        }
                    )
                }
            }
            .sheet(isPresented: sessionNoteSheetBinding) {
                if let vm = viewModel {
                    ExerciseNoteEditorSheet(
                        title: "Workout note",
                        initialNote: vm.sessionNoteSheetBody,
                        onSave: { vm.saveSessionNote($0) }
                    )
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = WorkoutLoggingViewModel(modelContext: modelContext, router: router)
                }
                viewModel?.loadFromRouter()
            }
            .onChange(of: router.selectedWorkoutId) { _, _ in
                viewModel?.loadFromRouter()
            }
            .onAppear {
                viewModel?.loadFromRouter()
            }
        }
    }

    private var sessionNoteSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.sessionNoteSheetPresented ?? false },
            set: { viewModel?.sessionNoteSheetPresented = $0 }
        )
    }
}

private struct FinishWorkoutSheet: View {
    @Bindable var viewModel: WorkoutLoggingViewModel
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Only sets you enter are saved. Values from your last workout are for reference only.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        viewModel.presentSessionNoteEditor()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "note.text")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Add/edit note")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if !viewModel.workoutSessionNotePreview.isEmpty {
                                    Text(viewModel.workoutSessionNotePreview)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                } else {
                                    Text("Optional reflection or cues for next time.")
                                        .font(.footnote)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workoutFinishSessionNoteBox")
                }
                .padding()
                .id(viewModel.sessionNoteRefreshStamp)
            }
            .navigationTitle("Finish workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish workout", action: onFinish)
                        .accessibilityIdentifier("workoutLogConfirmFinishButton")
                }
            }
        }
    }
}

private enum LoggingFieldFocus: Hashable {
    case weight(String)
    case reps(String)
    case cardioMinutes(String)
    case cardioMaxHeartRate(String)

    fileprivate var commitKey: String {
        switch self {
        case .weight(let id): return "w:\(id)"
        case .reps(let id): return "r:\(id)"
        case .cardioMinutes(let id): return "cm:\(id)"
        case .cardioMaxHeartRate(let id): return "chr:\(id)"
        }
    }

    /// The row a field belongs to (its `SetRow.id`) — used to tell a same-row field move (weight → reps) apart
    /// from a move to a different row, so same-row moves don't trigger a commit mid-transition (see `WorkoutLoggingContent`).
    fileprivate var rowId: String {
        switch self {
        case .weight(let id), .reps(let id), .cardioMinutes(let id), .cardioMaxHeartRate(let id):
            return id
        }
    }
}

private extension Notification.Name {
    /// `userInfo["commitKey"]` matches `LoggingFieldFocus.commitKey` so the correct row commits when focus moves or the keyboard dismisses.
    static let workoutLoggingCommitKeyedField = Notification.Name("workoutLoggingCommitKeyedField")
}

/// Deferred to the next run-loop tick: posting (and therefore the row commit → view-model save → section rebuild
/// it triggers) must not happen synchronously inside `.onChange(of: fieldFocus)` — mutating the row data source
/// while iOS's focus engine is still mid-transition to the newly focused field makes it drop focus to `nil`
/// instead of landing on that field (reproduced: moving from weight straight to reps closed the keyboard as if
/// Done had been tapped).
private func postWorkoutFieldCommit(_ focus: LoggingFieldFocus) {
    DispatchQueue.main.async {
        NotificationCenter.default.post(
            name: .workoutLoggingCommitKeyedField,
            object: nil,
            userInfo: ["commitKey": focus.commitKey]
        )
    }
}

/// Number pads have no Return key; SwiftUI’s keyboard toolbar often does not attach to fields inside `List`. Always use this to dismiss.
private func resignFirstResponderGlobally() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private struct WorkoutLoggingContent: View {
    @Bindable var viewModel: WorkoutLoggingViewModel
    @Environment(AppRouter.self) private var router
    @FocusState.Binding var fieldFocus: LoggingFieldFocus?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.sections.isEmpty {
                ProgressView()
            } else if router.selectedWorkoutId == nil, viewModel.workoutTitle == nil {
                ContentUnavailableView(
                    "No workout open",
                    systemImage: "figure.walk",
                    description: Text("On Today, tap Start on a workout day to log sets here.")
                )
            } else if let err = viewModel.errorMessage {
                ContentUnavailableView("Couldn’t load", systemImage: "exclamationmark.triangle", description: Text(err))
            } else {
                List {
                    ForEach(viewModel.sections) { section in
                        Section {
                            ForEach(section.rows) { row in
                                Group {
                                    if section.kind == .cardio {
                                        WorkoutCardioSetRowView(
                                            row: row,
                                            focusField: $fieldFocus,
                                            onCommitRow: { minutes, maxHR, mark in
                                                viewModel.updateCardioLoggedSet(
                                                    exerciseId: row.exerciseId,
                                                    setIndex: row.setIndex,
                                                    minutes: minutes,
                                                    maxHeartRate: maxHR,
                                                    markUserEntry: mark
                                                )
                                            }
                                        )
                                    } else {
                                        WorkoutSetRowView(
                                            row: row,
                                            repsArePerSide: section.repsArePerSide,
                                            focusField: $fieldFocus,
                                            onCommitRow: { w, r, mark in
                                                viewModel.updateLoggedSet(
                                                    exerciseId: row.exerciseId,
                                                    setIndex: row.setIndex,
                                                    weight: w,
                                                    reps: r,
                                                    markUserEntry: mark
                                                )
                                            }
                                        )
                                    }
                                }
                                .listRowBackground(Color.clear)
                            }
                        } header: {
                            Button {
                                viewModel.presentExerciseNote(exerciseId: section.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(section.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Spacer(minLength: 0)
                                        if section.hasNote {
                                            Image(systemName: "note.text")
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    if section.repsArePerSide {
                                        Label("Per side — volume counts both sides (×2)", systemImage: "arrow.left.and.right")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens note editor for this exercise")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: fieldFocus) { oldValue, newValue in
                    guard oldValue != newValue else { return }
                    // Moving between a row's own fields (weight -> reps) must not commit mid-transition — doing
                    // so rebuilds the row list while iOS's focus engine is still landing on the new field, which
                    // drops focus to nil instead (closes the keyboard as if Done had been tapped). Only commit
                    // when focus actually leaves the row (a different row, Done, or dismissal).
                    if let old = oldValue, old.rowId != newValue?.rowId {
                        postWorkoutFieldCommit(old)
                    }
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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if viewModel.workoutTitle != nil, !viewModel.sections.isEmpty {
                        VStack(spacing: 0) {
                            if fieldFocus != nil {
                                Button {
                                    if let f = fieldFocus {
                                        postWorkoutFieldCommit(f)
                                    }
                                    fieldFocus = nil
                                    resignFirstResponderGlobally()
                                } label: {
                                    Text("Done")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.borderedProminent)
                                .padding(.horizontal)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                                .background(.bar)
                                .accessibilityIdentifier("workoutLogKeyboardDoneButton")
                            }
                            HStack {
                                Text("Session volume")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(viewModel.sessionVolumeLabel)
                                    .font(.headline.monospacedDigit())
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .background(.bar)

                            Button {
                                viewModel.presentSessionNoteEditor()
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.pencil")
                                        .font(.body.weight(.medium))
                                    Text(viewModel.hasWorkoutSessionNote ? "Edit workout note" : "Add a note")
                                    Spacer()
                                    if viewModel.hasWorkoutSessionNote {
                                        Image(systemName: "note.text")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.bar)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("workoutLogSessionNoteButton")
                        }
                        .id(viewModel.sessionNoteRefreshStamp)
                    }
                }
            }
        }
    }
}

private struct WorkoutSetRowView: View {
    let row: WorkoutLoggingViewModel.SetRow
    var repsArePerSide: Bool
    var focusField: FocusState<LoggingFieldFocus?>.Binding
    let onCommitRow: (Double, Int, Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var weightText = ""
    @State private var repsText = ""
    /// Captured when the weight field gains focus (nil = user has not focused that field this “visit”).
    @State private var weightSnapshotOnFocus: String?
    /// Captured when the reps field gains focus.
    @State private var repsSnapshotOnFocus: String?

    private var rowFocusId: String { row.id }

    /// Styling for weight/rep boxes: previous-session values are orange + white; after the user commits entry, dark/light filled + contrasting text.
    private enum SetFieldChrome {
        case neutral
        case previousSession
        case userEntered
    }

    private var setFieldChrome: SetFieldChrome {
        if row.isEntered { return .userEntered }
        if row.referenceWeight > 0 || row.referenceReps > 0 { return .previousSession }
        return .neutral
    }

    private var previousSessionFieldFill: Color {
        Color(red: 0.9, green: 0.45, blue: 0.05)
    }

    private var enteredFieldFill: Color {
        colorScheme == .dark ? Color(white: 0.95) : Color.black
    }

    private var enteredFieldForeground: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var fieldCaretTint: Color {
        switch setFieldChrome {
        case .neutral: return Color.accentColor
        case .previousSession: return .white
        case .userEntered: return enteredFieldForeground
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set \(row.setNumber)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                numericBlock(
                    label: "Weight (kg)",
                    text: $weightText,
                    focus: .weight(rowFocusId),
                    keyboard: .decimalPad,
                    onCommit: commitRowFromFields
                )
                numericBlock(
                    label: repsArePerSide ? "Reps / side" : "Reps",
                    text: $repsText,
                    focus: .reps(rowFocusId),
                    keyboard: .numberPad,
                    onCommit: commitRowFromFields
                )
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            weightSnapshotOnFocus = nil
            repsSnapshotOnFocus = nil
            syncFieldsFromRow()
        }
        .onChange(of: row.id) { _, _ in
            weightSnapshotOnFocus = nil
            repsSnapshotOnFocus = nil
            syncFieldsFromRow()
        }
        .onChange(of: row.isEntered) { _, _ in
            weightSnapshotOnFocus = nil
            repsSnapshotOnFocus = nil
            syncFieldsFromRow()
        }
        .onChange(of: focusField.wrappedValue) { _, new in
            switch new {
            case .weight(let id) where id == rowFocusId:
                weightSnapshotOnFocus = weightText
            case .reps(let id) where id == rowFocusId:
                repsSnapshotOnFocus = repsText
            default:
                break
            }
        }
        .onChange(of: row.weight) { _, _ in
            if focusField.wrappedValue != .weight(rowFocusId) { syncWeightFromRow() }
        }
        .onChange(of: row.reps) { _, _ in
            if focusField.wrappedValue != .reps(rowFocusId) { syncRepsFromRow() }
        }
        .onChange(of: row.referenceWeight) { _, _ in
            if focusField.wrappedValue != .weight(rowFocusId) { syncWeightFromRow() }
        }
        .onChange(of: row.referenceReps) { _, _ in
            if focusField.wrappedValue != .reps(rowFocusId) { syncRepsFromRow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutLoggingCommitKeyedField)) { note in
            guard let key = note.userInfo?["commitKey"] as? String else { return }
            if key == "w:\(rowFocusId)" || key == "r:\(rowFocusId)" {
                commitRowFromFields()
            }
        }
    }

    private func commitRowFromFields() {
        let w = parsedWeight(from: weightText)
        let r = parsedReps(from: repsText)
        let mark = shouldMarkUserEntry(parsedW: w, parsedR: r)
        onCommitRow(w, r, mark)
    }

    private func shouldMarkUserEntry(parsedW: Double, parsedR: Int) -> Bool {
        if row.isEntered { return true }
        // After focusing weight or reps, any commit counts as today’s entry (including matching reference).
        let touchedSinceFocus =
            weightSnapshotOnFocus != nil || repsSnapshotOnFocus != nil
        if touchedSinceFocus {
            return true
        }
        let wDirty = abs(parsedW - row.referenceWeight) > 1e-6
        let rDirty = parsedR != row.referenceReps
        return wDirty || rDirty
    }

    private func normalizedWeightText(_ s: String) -> String {
        s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parsedWeight(from text: String) -> Double {
        let n = normalizedWeightText(text)
        let v = Double(n) ?? 0
        return max(0, v)
    }

    private func parsedReps(from text: String) -> Int {
        let v = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return max(0, v)
    }

    private func syncFieldsFromRow() {
        syncWeightFromRow()
        syncRepsFromRow()
    }

    private func syncWeightFromRow() {
        if row.isEntered {
            if row.weight == 0 {
                weightText = ""
            } else if row.weight == floor(row.weight) {
                weightText = String(Int(row.weight))
            } else {
                weightText = String(row.weight)
            }
        } else if row.referenceWeight == 0 {
            weightText = ""
        } else if row.referenceWeight == floor(row.referenceWeight) {
            weightText = String(Int(row.referenceWeight))
        } else {
            weightText = String(row.referenceWeight)
        }
    }

    private func syncRepsFromRow() {
        if row.isEntered {
            repsText = row.reps == 0 ? "" : "\(row.reps)"
        } else if row.referenceReps == 0 {
            repsText = ""
        } else {
            repsText = "\(row.referenceReps)"
        }
    }

    private func numericBlock(
        label: String,
        text: Binding<String>,
        focus: LoggingFieldFocus,
        keyboard: UIKeyboardType,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Group {
                switch setFieldChrome {
                case .neutral:
                    TextField(
                        "",
                        text: text,
                        prompt: Text("0").foregroundStyle(.tertiary)
                    )
                    .keyboardType(keyboard)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                case .previousSession:
                    TextField(
                        "",
                        text: text,
                        prompt: Text("0").foregroundStyle(.white.opacity(0.55))
                    )
                    .keyboardType(keyboard)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    .background(previousSessionFieldFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHint("Value from your last completed session for this workout.")
                case .userEntered:
                    TextField(
                        "",
                        text: text,
                        prompt: Text("0").foregroundStyle(enteredFieldForeground.opacity(0.45))
                    )
                    .keyboardType(keyboard)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(enteredFieldForeground)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    .background(enteredFieldFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .tint(fieldCaretTint)
            .focused(focusField, equals: focus)
            .frame(minHeight: 44)
            .onSubmit(onCommit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Cardio counterpart of `WorkoutSetRowView`: minutes + max heart rate instead of weight/reps, same chrome/commit behavior.
private struct WorkoutCardioSetRowView: View {
    let row: WorkoutLoggingViewModel.SetRow
    var focusField: FocusState<LoggingFieldFocus?>.Binding
    let onCommitRow: (Double, Int, Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var minutesText = ""
    @State private var maxHRText = ""
    @State private var minutesSnapshotOnFocus: String?
    @State private var maxHRSnapshotOnFocus: String?

    private var rowFocusId: String { row.id }

    private enum SetFieldChrome {
        case neutral
        case previousSession
        case userEntered
    }

    private var setFieldChrome: SetFieldChrome {
        if row.isEntered { return .userEntered }
        if row.referenceCardioMinutes > 0 || row.referenceMaxHeartRate > 0 { return .previousSession }
        return .neutral
    }

    private var previousSessionFieldFill: Color {
        Color(red: 0.9, green: 0.45, blue: 0.05)
    }

    private var enteredFieldFill: Color {
        colorScheme == .dark ? Color(white: 0.95) : Color.black
    }

    private var enteredFieldForeground: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var fieldCaretTint: Color {
        switch setFieldChrome {
        case .neutral: return Color.accentColor
        case .previousSession: return .white
        case .userEntered: return enteredFieldForeground
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set \(row.setNumber)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                numericBlock(
                    label: "Minutes",
                    text: $minutesText,
                    focus: .cardioMinutes(rowFocusId),
                    keyboard: .decimalPad,
                    onCommit: commitRowFromFields
                )
                numericBlock(
                    label: "Max HR (bpm)",
                    text: $maxHRText,
                    focus: .cardioMaxHeartRate(rowFocusId),
                    keyboard: .numberPad,
                    onCommit: commitRowFromFields
                )
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            minutesSnapshotOnFocus = nil
            maxHRSnapshotOnFocus = nil
            syncFieldsFromRow()
        }
        .onChange(of: row.id) { _, _ in
            minutesSnapshotOnFocus = nil
            maxHRSnapshotOnFocus = nil
            syncFieldsFromRow()
        }
        .onChange(of: row.isEntered) { _, _ in
            minutesSnapshotOnFocus = nil
            maxHRSnapshotOnFocus = nil
            syncFieldsFromRow()
        }
        .onChange(of: focusField.wrappedValue) { _, new in
            switch new {
            case .cardioMinutes(let id) where id == rowFocusId:
                minutesSnapshotOnFocus = minutesText
            case .cardioMaxHeartRate(let id) where id == rowFocusId:
                maxHRSnapshotOnFocus = maxHRText
            default:
                break
            }
        }
        .onChange(of: row.cardioMinutes) { _, _ in
            if focusField.wrappedValue != .cardioMinutes(rowFocusId) { syncMinutesFromRow() }
        }
        .onChange(of: row.maxHeartRate) { _, _ in
            if focusField.wrappedValue != .cardioMaxHeartRate(rowFocusId) { syncMaxHRFromRow() }
        }
        .onChange(of: row.referenceCardioMinutes) { _, _ in
            if focusField.wrappedValue != .cardioMinutes(rowFocusId) { syncMinutesFromRow() }
        }
        .onChange(of: row.referenceMaxHeartRate) { _, _ in
            if focusField.wrappedValue != .cardioMaxHeartRate(rowFocusId) { syncMaxHRFromRow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutLoggingCommitKeyedField)) { note in
            guard let key = note.userInfo?["commitKey"] as? String else { return }
            if key == "cm:\(rowFocusId)" || key == "chr:\(rowFocusId)" {
                commitRowFromFields()
            }
        }
    }

    private func commitRowFromFields() {
        let m = parsedMinutes(from: minutesText)
        let hr = parsedMaxHR(from: maxHRText)
        let mark = shouldMarkUserEntry(parsedM: m, parsedHR: hr)
        onCommitRow(m, hr, mark)
    }

    private func shouldMarkUserEntry(parsedM: Double, parsedHR: Int) -> Bool {
        if row.isEntered { return true }
        let touchedSinceFocus = minutesSnapshotOnFocus != nil || maxHRSnapshotOnFocus != nil
        if touchedSinceFocus {
            return true
        }
        let mDirty = abs(parsedM - row.referenceCardioMinutes) > 1e-6
        let hrDirty = parsedHR != row.referenceMaxHeartRate
        return mDirty || hrDirty
    }

    private func normalizedMinutesText(_ s: String) -> String {
        s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parsedMinutes(from text: String) -> Double {
        let n = normalizedMinutesText(text)
        let v = Double(n) ?? 0
        return max(0, v)
    }

    private func parsedMaxHR(from text: String) -> Int {
        let v = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return max(0, v)
    }

    private func syncFieldsFromRow() {
        syncMinutesFromRow()
        syncMaxHRFromRow()
    }

    private func syncMinutesFromRow() {
        if row.isEntered {
            if row.cardioMinutes == 0 {
                minutesText = ""
            } else if row.cardioMinutes == floor(row.cardioMinutes) {
                minutesText = String(Int(row.cardioMinutes))
            } else {
                minutesText = String(row.cardioMinutes)
            }
        } else if row.referenceCardioMinutes == 0 {
            minutesText = ""
        } else if row.referenceCardioMinutes == floor(row.referenceCardioMinutes) {
            minutesText = String(Int(row.referenceCardioMinutes))
        } else {
            minutesText = String(row.referenceCardioMinutes)
        }
    }

    private func syncMaxHRFromRow() {
        if row.isEntered {
            maxHRText = row.maxHeartRate == 0 ? "" : "\(row.maxHeartRate)"
        } else if row.referenceMaxHeartRate == 0 {
            maxHRText = ""
        } else {
            maxHRText = "\(row.referenceMaxHeartRate)"
        }
    }

    private func numericBlock(
        label: String,
        text: Binding<String>,
        focus: LoggingFieldFocus,
        keyboard: UIKeyboardType,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Group {
                switch setFieldChrome {
                case .neutral:
                    TextField(
                        "",
                        text: text,
                        prompt: Text("0").foregroundStyle(.tertiary)
                    )
                    .keyboardType(keyboard)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                case .previousSession:
                    TextField(
                        "",
                        text: text,
                        prompt: Text("0").foregroundStyle(.white.opacity(0.55))
                    )
                    .keyboardType(keyboard)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    .background(previousSessionFieldFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHint("Value from your last completed session for this workout.")
                case .userEntered:
                    TextField(
                        "",
                        text: text,
                        prompt: Text("0").foregroundStyle(enteredFieldForeground.opacity(0.45))
                    )
                    .keyboardType(keyboard)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(enteredFieldForeground)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    .background(enteredFieldFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .tint(fieldCaretTint)
            .focused(focusField, equals: focus)
            .frame(minHeight: 44)
            .onSubmit(onCommit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let router = AppRouter()
    if let program = try? ProgramRepository(modelContext: context).activeProgram(),
       let firstWorkout = program.workouts.first {
        router.selectedWorkoutId = firstWorkout.id
    }
    return WorkoutLoggingScreen()
        .modelContainer(container)
        .environment(router)
}

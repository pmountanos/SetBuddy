//
//  ImportViewModel.swift
//  Set Buddy
//

import Foundation
import SwiftData

/// Spreadsheet import staging and confirmation — the Program import controls in Settings.
@MainActor
@Observable
final class ImportViewModel {
    private static let importScheduleStartDateKey = "importScheduleStartDateSince1970"

    var importMessage: String?
    var importError: String?
    var isImporting = false

    /// Shown after picking a file; user chooses cycle offset and confirms import.
    var importStagingPresented = false
    var stagedImportProgramName: String?
    /// Parsed once in `stageImportFromPickedFile`; reused on confirm instead of re-parsing the workbook.
    private var stagedCycle: [XlsxCycleDay]?
    var stagedCycleDayLabels: [String] = []
    var stagedSelectedCycleDayIndex: Int = 0

    /// Exact-name matches against the program being replaced — applied without asking; count shown for reassurance.
    private var stagedAutoCarryover: [ImportExerciseRef: UUID] = [:]
    var stagedAutoCarryoverCount: Int { stagedAutoCarryover.count }
    /// Close-but-not-exact matches, offered for the user to confirm before being carried over.
    var stagedCarryoverSuggestions: [ExerciseCarryoverMatcher.Suggestion] = []
    /// Suggestion ids the user wants applied; defaults to all suggestions since `>= 75%` similarity is usually right.
    var stagedConfirmedSuggestionIds: Set<UUID> = []

    /// First calendar day mapped to worksheet 1 (tab order) when importing.
    var importScheduleStartDate: Date {
        didSet {
            UserDefaults.standard.set(
                importScheduleStartDate.timeIntervalSince1970,
                forKey: Self.importScheduleStartDateKey
            )
        }
    }

    init() {
        if let interval = UserDefaults.standard.object(forKey: Self.importScheduleStartDateKey) as? TimeInterval {
            importScheduleStartDate = Date(timeIntervalSince1970: interval)
        } else {
            importScheduleStartDate = Date()
        }
    }

    /// Reads and validates the spreadsheet, matches its exercises against the program being replaced (by name, for
    /// carrying reference weights forward), then opens the staging sheet.
    func stageImportFromPickedFile(url: URL, modelContext: ModelContext) {
        importMessage = nil
        importError = nil
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let cycle = try ProgramXlsxParser.parse(xlsxData: data)
            guard !cycle.isEmpty else {
                importError = "That spreadsheet has no workout days to import."
                return
            }
            stagedCycle = cycle
            let fileTitle = url.deletingPathExtension().lastPathComponent
            stagedImportProgramName = ImportedProgramDisplayNaming.programName(fromSpreadsheetFileName: fileTitle)
            stagedCycleDayLabels = cycle.enumerated().map { index, day in
                let n = index + 1
                if day.isRestDay {
                    return "\(n). \(day.sheetName) — Rest"
                }
                return "\(n). \(day.sheetName)"
            }
            stagedSelectedCycleDayIndex = 0

            let existingExercises = try existingExercisesForCarryover(modelContext: modelContext)
            let matchResult = ExerciseCarryoverMatcher.match(existing: existingExercises, newCycle: cycle)
            stagedAutoCarryover = matchResult.autoCarryover
            stagedCarryoverSuggestions = matchResult.suggestions
            stagedConfirmedSuggestionIds = Set(matchResult.suggestions.map(\.id))

            importStagingPresented = true
        } catch {
            importError = error.localizedDescription
        }
    }

    private func existingExercisesForCarryover(modelContext: ModelContext) throws -> [ExerciseCarryoverMatcher.ExistingExercise] {
        guard let program = try ProgramRepository(modelContext: modelContext).activeProgram() else { return [] }
        return program.workouts.flatMap { workout in
            workout.exercises.map { ExerciseCarryoverMatcher.ExistingExercise(id: $0.id, name: $0.name) }
        }
    }

    func cancelStagedImport() {
        importStagingPresented = false
        stagedCycle = nil
        stagedImportProgramName = nil
        stagedCycleDayLabels = []
        stagedSelectedCycleDayIndex = 0
        stagedAutoCarryover = [:]
        stagedCarryoverSuggestions = []
        stagedConfirmedSuggestionIds = []
    }

    func confirmStagedImport(modelContext: ModelContext) async {
        guard let cycle = stagedCycle, let name = stagedImportProgramName else {
            cancelStagedImport()
            return
        }
        isImporting = true
        importMessage = nil
        importError = nil
        defer {
            isImporting = false
            cancelStagedImport()
        }
        let calendar = Calendar.current
        let start = CalendarDate(from: importScheduleStartDate, calendar: calendar)
        var exerciseCarryover = stagedAutoCarryover
        for suggestion in stagedCarryoverSuggestions where stagedConfirmedSuggestionIds.contains(suggestion.id) {
            exerciseCarryover[suggestion.newExercise] = suggestion.oldExerciseId
        }
        let carriedOverCount = exerciseCarryover.count
        do {
            try ProgramXlsxImporter.importReplacingStore(
                cycle: cycle,
                programName: name,
                startDate: start,
                modelContext: modelContext,
                calendar: calendar,
                cycleStartIndex: stagedSelectedCycleDayIndex,
                exerciseCarryover: exerciseCarryover
            )
            let carryoverNote = carriedOverCount > 0
                ? " Reference weights carried over for \(carriedOverCount) matching exercise\(carriedOverCount == 1 ? "" : "s")."
                : ""
            importMessage = "Imported “\(name)”. Your program and schedule were replaced. Completed workouts are still in History; any workout in progress was cleared.\(carryoverNote)"
            DailyNotificationScheduler.requestReschedule(modelContext: modelContext)
        } catch {
            importError = error.localizedDescription
        }
    }
}

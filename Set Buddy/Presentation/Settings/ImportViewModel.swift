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

    /// Reads and validates the spreadsheet, then opens the staging sheet (cycle picker + start date).
    func stageImportFromPickedFile(url: URL) {
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
            importStagingPresented = true
        } catch {
            importError = error.localizedDescription
        }
    }

    func cancelStagedImport() {
        importStagingPresented = false
        stagedCycle = nil
        stagedImportProgramName = nil
        stagedCycleDayLabels = []
        stagedSelectedCycleDayIndex = 0
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
        do {
            try ProgramXlsxImporter.importReplacingStore(
                cycle: cycle,
                programName: name,
                startDate: start,
                modelContext: modelContext,
                calendar: calendar,
                cycleStartIndex: stagedSelectedCycleDayIndex
            )
            importMessage = "Imported “\(name)”. Your program and schedule were replaced. Completed workouts are still in History; any workout in progress was cleared."
            DailyNotificationScheduler.requestReschedule(modelContext: modelContext)
        } catch {
            importError = error.localizedDescription
        }
    }
}

//
//  SettingsViewModel.swift
//  Set Buddy
//

import Foundation
import SwiftData
import UserNotifications

/// Active share sheet for an export file in `temporaryDirectory`.
struct ExportPresentation: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
@Observable
final class SettingsViewModel {
    private static let importScheduleStartDateKey = "importScheduleStartDateSince1970"

    var importMessage: String?
    var importError: String?
    var exportError: String?
    var isImporting = false

    /// Shown after picking a file; user chooses cycle offset and confirms import.
    var importStagingPresented = false
    var stagedImportProgramName: String?
    private var stagedImportData: Data?
    var stagedCycleDayLabels: [String] = []
    var stagedSelectedCycleDayIndex: Int = 0

    /// User-facing status for the Notifications section (system authorization).
    var notificationAuthorizationExplanation: String = ""
    var notificationShowAllowButton = false
    var notificationShowOpenSettingsButton = false

    /// First calendar day mapped to worksheet 1 (tab order) when importing.
    var importScheduleStartDate: Date {
        didSet {
            UserDefaults.standard.set(
                importScheduleStartDate.timeIntervalSince1970,
                forKey: Self.importScheduleStartDateKey
            )
        }
    }

    /// Master switch for scheduling daily plan reminders (stored in `NotificationSettings`).
    var dailyNotificationsEnabled: Bool {
        didSet {
            persistNotificationSettings()
        }
    }

    /// Time-of-day for the daily reminder; calendar date is ignored.
    var notificationReminderTime: Date {
        didSet {
            persistNotificationSettings()
        }
    }

    /// Row count for the Program tab’s upcoming schedule list (7 / 14 / 21).
    var upcomingScheduleListDayCount: Int

    /// Share sheet for a generated export file.
    var exportPresentation: ExportPresentation?
    var isExporting = false

    init() {
        let ns = NotificationSettings.load()
        dailyNotificationsEnabled = ns.dailyRemindersEnabled
        notificationReminderTime = Calendar.current.date(
            bySettingHour: ns.hour,
            minute: ns.minute,
            second: 0,
            of: Date()
        ) ?? Date()

        if let interval = UserDefaults.standard.object(forKey: Self.importScheduleStartDateKey) as? TimeInterval {
            importScheduleStartDate = Date(timeIntervalSince1970: interval)
        } else {
            importScheduleStartDate = Date()
        }

        upcomingScheduleListDayCount = ProgramSchedulePreviewDaysSetting.load()
    }

    func setUpcomingScheduleListDayCount(_ days: Int) {
        guard ProgramSchedulePreviewDaysSetting.choices.contains(days) else { return }
        upcomingScheduleListDayCount = days
        ProgramSchedulePreviewDaysSetting.save(days)
    }

    private func persistNotificationSettings() {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: notificationReminderTime)
        let minute = cal.component(.minute, from: notificationReminderTime)
        NotificationSettings(
            dailyRemindersEnabled: dailyNotificationsEnabled,
            hour: hour,
            minute: minute
        ).save()
    }

    func refreshNotificationAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let status = settings.authorizationStatus
        notificationShowAllowButton = status == .notDetermined
        notificationShowOpenSettingsButton = status == .denied
        switch status {
        case .authorized, .provisional, .ephemeral:
            notificationAuthorizationExplanation = "System permission is on. Reminders use your chosen time when the toggle above is on."
        case .denied:
            notificationAuthorizationExplanation = "Notifications are turned off for Set Buddy. Use “Open system settings” to enable alerts."
        case .notDetermined:
            notificationAuthorizationExplanation = "Allow notifications so Set Buddy can remind you on workout and rest days."
        @unknown default:
            notificationAuthorizationExplanation = ""
        }
    }

    func requestNotificationAuthorizationAndReschedule(modelContext: ModelContext) async {
        _ = await NotificationPermission.requestAuthorization()
        await refreshNotificationAuthorizationStatus()
        await DailyNotificationScheduler.shared.reschedule(modelContext: modelContext)
    }

    func rescheduleNotifications(modelContext: ModelContext) async {
        await DailyNotificationScheduler.shared.reschedule(modelContext: modelContext)
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
            stagedImportData = data
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
        stagedImportData = nil
        stagedImportProgramName = nil
        stagedCycleDayLabels = []
        stagedSelectedCycleDayIndex = 0
    }

    private static func stampedExportFileName(prefix: String, ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        let ts = f.string(from: Date())
        return "\(prefix)_\(ts).\(ext)"
    }

    /// Writes `Set_Buddy_Program_yyyy-MM-dd_HHmmss.xlsx` (or `.csv` if the workbook cannot be built) and opens the share sheet.
    func exportProgram(modelContext: ModelContext) {
        exportError = nil
        isExporting = true
        defer { isExporting = false }
        do {
            let repo = ProgramRepository(modelContext: modelContext)
            guard let program = try repo.activeProgram() else {
                exportError = ExportError.noActiveProgram.localizedDescription
                return
            }
            let base = FileManager.default.temporaryDirectory
            let xlsxName = Self.stampedExportFileName(prefix: "Set_Buddy_Program", ext: "xlsx")
            let xlsxURL = base.appendingPathComponent(xlsxName)
            if let data = try? ProgramSpreadsheetExport.buildXlsx(program: program) {
                try data.write(to: xlsxURL, options: .atomic)
                exportPresentation = ExportPresentation(url: xlsxURL)
                return
            }
            let csvName = Self.stampedExportFileName(prefix: "Set_Buddy_Program", ext: "csv")
            let csvURL = base.appendingPathComponent(csvName)
            let csvData = try ProgramSpreadsheetExport.buildCsv(program: program, calendar: .current)
            try csvData.write(to: csvURL, options: .atomic)
            exportPresentation = ExportPresentation(url: csvURL)
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// Writes `Set_Buddy_History_yyyy-MM-dd_HHmmss.xlsx` (or `.csv` fallback) with one row per logged set.
    func exportHistory(modelContext: ModelContext) {
        exportError = nil
        isExporting = true
        defer { isExporting = false }
        do {
            let sessions = try HistoryRepository(modelContext: modelContext).allCompletedSessionDetails()
            let base = FileManager.default.temporaryDirectory
            let xlsxName = Self.stampedExportFileName(prefix: "Set_Buddy_History", ext: "xlsx")
            let xlsxURL = base.appendingPathComponent(xlsxName)
            if let data = try? HistorySpreadsheetExport.buildXlsx(sessions: sessions) {
                try data.write(to: xlsxURL, options: .atomic)
                exportPresentation = ExportPresentation(url: xlsxURL)
                return
            }
            let csvName = Self.stampedExportFileName(prefix: "Set_Buddy_History", ext: "csv")
            let csvURL = base.appendingPathComponent(csvName)
            let csvData = try HistorySpreadsheetExport.buildCsv(sessions: sessions)
            try csvData.write(to: csvURL, options: .atomic)
            exportPresentation = ExportPresentation(url: csvURL)
        } catch {
            exportError = error.localizedDescription
        }
    }

    func finishExportSharing() {
        if let url = exportPresentation?.url {
            try? FileManager.default.removeItem(at: url)
        }
        exportPresentation = nil
    }

    func confirmStagedImport(modelContext: ModelContext) async {
        guard let data = stagedImportData, let name = stagedImportProgramName else {
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
                xlsx: data,
                programName: name,
                startDate: start,
                modelContext: modelContext,
                calendar: calendar,
                cycleStartIndex: stagedSelectedCycleDayIndex
            )
            importMessage = "Imported “\(name)”. Your program and schedule were replaced. Completed workouts are still in History; any workout in progress was cleared."
            await DailyNotificationScheduler.shared.reschedule(modelContext: modelContext)
        } catch {
            importError = error.localizedDescription
        }
    }
}

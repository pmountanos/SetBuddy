//
//  ExportViewModel.swift
//  Set Buddy
//

import Foundation
import SwiftData

/// Active share sheet for an export file in `temporaryDirectory`.
struct ExportPresentation: Identifiable {
    let id = UUID()
    let url: URL
}

/// Program/history spreadsheet export — the Export controls in Settings.
@MainActor
@Observable
final class ExportViewModel {
    var exportError: String?
    var isExporting = false

    /// Share sheet for a generated export file.
    var exportPresentation: ExportPresentation?

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
            let url = try writeExportFile(
                prefix: "Set_Buddy_Program",
                buildXlsx: { try ProgramSpreadsheetExport.buildXlsx(program: program) },
                buildCsv: { try ProgramSpreadsheetExport.buildCsv(program: program, calendar: .current) }
            )
            exportPresentation = ExportPresentation(url: url)
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
            let url = try writeExportFile(
                prefix: "Set_Buddy_History",
                buildXlsx: { try HistorySpreadsheetExport.buildXlsx(sessions: sessions) },
                buildCsv: { try HistorySpreadsheetExport.buildCsv(sessions: sessions) }
            )
            exportPresentation = ExportPresentation(url: url)
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

    /// Tries `buildXlsx` first; falls back to `buildCsv` if the workbook can't be built. Writes whichever succeeds to a
    /// stamped file in `temporaryDirectory` and returns its URL.
    private func writeExportFile(prefix: String, buildXlsx: () throws -> Data, buildCsv: () throws -> Data) throws -> URL {
        let base = FileManager.default.temporaryDirectory
        if let data = try? buildXlsx() {
            let url = base.appendingPathComponent(Self.stampedExportFileName(prefix: prefix, ext: "xlsx"))
            try data.write(to: url, options: .atomic)
            return url
        }
        let data = try buildCsv()
        let url = base.appendingPathComponent(Self.stampedExportFileName(prefix: prefix, ext: "csv"))
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func stampedExportFileName(prefix: String, ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        let ts = f.string(from: Date())
        return "\(prefix)_\(ts).\(ext)"
    }
}

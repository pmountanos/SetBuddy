//
//  ImportedProgramDisplayNaming.swift
//  Set Buddy
//

import Foundation

enum ImportedProgramDisplayNaming {
    /// Maps bundled / legacy spreadsheet base names to the canonical program title Set Buddy.
    static func programName(fromSpreadsheetFileName fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "workout buddy-2" || lower == "workout buddy" || lower == "workout buddy 2" {
            return "Set Buddy"
        }
        if lower == "set buddy-2" || lower == "set buddy 2" {
            return "Set Buddy"
        }
        return trimmed
    }

    /// Renames a persisted program that still uses an old default import title.
    static func normalizedStoredProgramName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "workout buddy-2" || lower == "workout buddy" || lower == "workout buddy 2" {
            return "Set Buddy"
        }
        if lower == "set buddy-2" || lower == "set buddy 2" {
            return "Set Buddy"
        }
        return nil
    }
}

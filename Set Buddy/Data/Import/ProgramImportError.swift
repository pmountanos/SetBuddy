//
//  ProgramImportError.swift
//  Set Buddy
//

import Foundation

enum ProgramImportError: LocalizedError, Equatable {
    case invalidXlsxArchive
    case missingZipEntry(String)
    case xmlParseFailed
    case workbookMissingSheets
    case emptyProgram

    var errorDescription: String? {
        switch self {
        case .invalidXlsxArchive:
            return "The file is not a valid Excel workbook (.xlsx)."
        case .missingZipEntry(let path):
            return "The workbook is missing required data (\(path))."
        case .xmlParseFailed:
            return "Could not read workbook XML."
        case .workbookMissingSheets:
            return "The workbook has no sheets."
        case .emptyProgram:
            return "No program days could be read from the workbook."
        }
    }
}

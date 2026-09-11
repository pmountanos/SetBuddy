//
//  ExportError.swift
//  Set Buddy
//

import Foundation

enum ExportError: LocalizedError {
    case noActiveProgram
    case couldNotCreateArchive
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noActiveProgram:
            return "There is no program to export. Create or import one on the Program tab."
        case .couldNotCreateArchive:
            return "Could not create the spreadsheet file."
        case .writeFailed:
            return "Could not write the export file."
        }
    }
}

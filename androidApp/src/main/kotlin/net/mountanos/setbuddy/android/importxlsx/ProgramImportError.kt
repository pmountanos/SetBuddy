package net.mountanos.setbuddy.android.importxlsx

/** Ported from `Data/Import/ProgramImportError.swift` — same cases, same user-facing message text. */
sealed class ProgramImportError(message: String) : Exception(message) {
    data object InvalidXlsxArchive :
        ProgramImportError("The file is not a valid Excel workbook (.xlsx).")

    data class MissingZipEntry(val path: String) :
        ProgramImportError("The workbook is missing required data ($path).")

    data object WorkbookMissingSheets :
        ProgramImportError("The workbook has no sheets.")

    data object EmptyProgram :
        ProgramImportError("No program days could be read from the workbook.")
}

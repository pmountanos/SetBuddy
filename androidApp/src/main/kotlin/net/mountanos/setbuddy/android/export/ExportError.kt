package net.mountanos.setbuddy.android.export

/** Ported from `Data/Export/ExportError.swift`. */
sealed class ExportError(message: String) : Exception(message) {
    data object NoActiveProgram :
        ExportError("There is no program to export. Create or import one on the Program tab.")

    data object CouldNotCreateArchive :
        ExportError("Could not create the spreadsheet file.")
}

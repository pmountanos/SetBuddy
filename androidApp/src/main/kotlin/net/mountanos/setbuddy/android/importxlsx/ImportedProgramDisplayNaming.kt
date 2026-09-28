package net.mountanos.setbuddy.android.importxlsx

/** Ported from `Platform/ImportedProgramDisplayNaming.swift`. */
object ImportedProgramDisplayNaming {
    private val legacyNames = setOf(
        "workout buddy", "workout buddy-2", "workout buddy 2",
        "set buddy-2", "set buddy 2",
    )

    /** [fileTitle] is the picked filename without its extension. */
    fun programName(fileTitle: String): String {
        val trimmed = fileTitle.trim()
        return if (trimmed.lowercase() in legacyNames) "Set Buddy" else trimmed
    }
}

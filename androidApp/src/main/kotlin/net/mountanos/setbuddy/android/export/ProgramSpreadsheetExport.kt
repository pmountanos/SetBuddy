package net.mountanos.setbuddy.android.export

import net.mountanos.setbuddy.domain.ProgramCalendarSchedule
import net.mountanos.setbuddy.domain.ScheduledDayKind
import net.mountanos.setbuddy.shared.data.ProgramOutline

/** Ported from `Data/Export/ProgramSpreadsheetExport.swift`. */
object ProgramSpreadsheetExport {
    private const val HEADER_NAME = "Exercise_Name"
    private const val HEADER_NOTES = "Notes"
    private const val HEADER_PER_SIDE = "Per side"
    private const val HEADER_TYPE = "Type"

    fun buildXlsx(outline: ProgramOutline): ByteArray {
        if (outline.workouts.isEmpty()) throw ExportError.NoActiveProgram
        val usedNames = mutableSetOf<String>()
        val sheets = outline.workouts.map { workout ->
            val rows = mutableListOf<List<Cell>>()
            rows.add(
                listOf(Cell.Text(HEADER_NAME), Cell.Text(HEADER_NOTES), Cell.Text(HEADER_PER_SIDE), Cell.Text(HEADER_TYPE)),
            )
            val sortedExercises = workout.exercises.sortedBy { it.sortOrder }
            for (ex in sortedExercises) {
                rows.add(
                    listOf(
                        Cell.Text(ex.name),
                        Cell.Text(ex.note ?: ""),
                        Cell.Text(if (ex.repsArePerSide) "x" else ""),
                        Cell.Text(ex.kind.rawValue),
                    ),
                )
            }
            if (sortedExercises.isEmpty()) rows.add(listOf(Cell.Text(""), Cell.Text(""), Cell.Text(""), Cell.Text("")))
            MinimalXlsxArchive.Sheet(uniqueSheetName(workout.name, usedNames), SpreadsheetFormatting.worksheetXml(rows))
        }
        return MinimalXlsxArchive.makeWorkbook(sheets)
    }

    fun buildCsv(outline: ProgramOutline, schedule: ProgramCalendarSchedule): ByteArray {
        val lines = mutableListOf<String>()
        lines.add("kind,program_name,,,")
        lines.add("program,${csv(outline.programName)},,,")
        for (workout in outline.workouts) {
            lines.add("workout,${csv(workout.name)},,,")
            lines.add("column,sort_order,exercise_name,set_count,note,per_side,type")
            for (ex in workout.exercises.sortedBy { it.sortOrder }) {
                lines.add(
                    "exercise,${ex.sortOrder},${csv(ex.name)},${ex.setCount},${csv(ex.note ?: "")}," +
                        (if (ex.repsArePerSide) "yes" else "no") + ",${ex.kind.rawValue}",
                )
            }
        }
        lines.add("kind,schedule_date,rest_or_workout,workout_name,")
        val titleByWorkoutId = outline.workouts.associate { it.id to it.name }
        for ((date, kind) in schedule.allEntries) {
            val dateStr = "%04d-%02d-%02d".format(date.year, date.month, date.day)
            when (kind) {
                is ScheduledDayKind.Rest -> lines.add("schedule,$dateStr,rest,,")
                is ScheduledDayKind.Workout -> {
                    val name = titleByWorkoutId[kind.workoutId]
                    lines.add(
                        if (name != null) "schedule,$dateStr,workout,${csv(name)}," else "schedule,$dateStr,unknown,,",
                    )
                }
            }
        }
        return SpreadsheetFormatting.csvBytes(lines)
    }

    private fun csv(s: String) = SpreadsheetFormatting.csvEscape(s)

    private fun uniqueSheetName(rawName: String, used: MutableSet<String>): String {
        var base = rawName.filterNot { it in ":\\/?*[]" }.trim()
        if (base.isEmpty()) base = "Workout"
        if (base.length > 31) base = base.substring(0, 31)
        var candidate = base
        var suffixIndex = 2
        while (candidate in used) {
            val suffix = " ($suffixIndex)"
            val maxBaseLen = 31 - suffix.length
            val truncatedBase = if (base.length > maxBaseLen) base.substring(0, maxBaseLen) else base
            candidate = truncatedBase + suffix
            suffixIndex++
        }
        used.add(candidate)
        return candidate
    }
}

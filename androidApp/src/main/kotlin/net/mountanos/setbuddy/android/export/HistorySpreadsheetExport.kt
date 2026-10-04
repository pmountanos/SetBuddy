package net.mountanos.setbuddy.android.export

import net.mountanos.setbuddy.shared.data.HistorySessionDetail
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Ported from `Data/Export/HistorySpreadsheetExport.swift`. */
object HistorySpreadsheetExport {
    private val headers = listOf(
        "completed_at", "workout", "schedule_day", "total_volume", "exercise",
        "set_number", "weight_kg", "reps", "per_side", "set_volume", "session_note",
        "type", "cardio_minutes", "max_heart_rate",
    )

    fun buildXlsx(sessions: List<HistorySessionDetail>): ByteArray {
        val rows = mutableListOf<List<Cell>>()
        rows.add(headers.map { Cell.Text(it) })
        if (sessions.isEmpty()) {
            rows.add(
                listOf(
                    Cell.Text(""), Cell.Text(""), Cell.Text(""), Cell.Number(0.0), Cell.Text(""),
                    Cell.Number(0.0), Cell.Number(0.0), Cell.Number(0.0), Cell.Text("no"), Cell.Number(0.0), Cell.Text(""),
                    Cell.Text(""), Cell.Number(0.0), Cell.Number(0.0),
                ),
            )
        } else {
            for (session in sessions) appendSessionRows(session, rows)
        }
        return MinimalXlsxArchive.makeWorkbook(
            listOf(MinimalXlsxArchive.Sheet("History", SpreadsheetFormatting.worksheetXml(rows))),
        )
    }

    fun buildCsv(sessions: List<HistorySessionDetail>): ByteArray {
        val lines = mutableListOf<String>()
        lines.add(headers.joinToString(","))
        for (session in sessions) appendSessionCsvLines(session, lines)
        return SpreadsheetFormatting.csvBytes(lines)
    }

    private fun completedAtLabel(epochMillis: Long): String {
        if (epochMillis == 0L) return ""
        return SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(epochMillis))
    }

    private fun scheduleDayLabel(session: HistorySessionDetail): String =
        "%04d-%02d-%02d".format(session.scheduleDate.year, session.scheduleDate.month, session.scheduleDate.day)

    private fun appendSessionRows(session: HistorySessionDetail, rows: MutableList<List<Cell>>) {
        val completedAt = completedAtLabel(session.completedAtEpochMillis)
        val scheduleDay = scheduleDayLabel(session)
        val note = session.sessionNote ?: ""
        var setVolumeSum = 0.0
        for (group in session.exerciseGroups) {
            for (line in group.sets) {
                setVolumeSum += line.volume
                rows.add(
                    listOf(
                        Cell.Text(completedAt), Cell.Text(session.title), Cell.Text(scheduleDay),
                        Cell.Number(session.totalVolume), Cell.Text(group.exerciseName),
                        Cell.Number((line.setIndex + 1).toDouble()), Cell.Number(line.weight),
                        Cell.Number(line.reps.toDouble()), Cell.Text(if (line.repsArePerSide) "yes" else "no"),
                        Cell.Number(line.volume), Cell.Text(note),
                        Cell.Text(line.kind.rawValue), Cell.Number(line.cardioMinutes),
                        Cell.Number(line.maxHeartRate.toDouble()),
                    ),
                )
            }
        }
        rows.add(
            listOf(
                Cell.Text(completedAt), Cell.Text(session.title), Cell.Text(scheduleDay),
                Cell.Number(session.totalVolume), Cell.Text("workout_total"),
                Cell.Text(""), Cell.Text(""), Cell.Text(""), Cell.Text(""),
                Cell.Number(setVolumeSum), Cell.Text(note),
                Cell.Text(""), Cell.Text(""), Cell.Text(""),
            ),
        )
    }

    private fun appendSessionCsvLines(session: HistorySessionDetail, lines: MutableList<String>) {
        val completedAt = completedAtLabel(session.completedAtEpochMillis)
        val scheduleDay = scheduleDayLabel(session)
        val note = SpreadsheetFormatting.csvEscape(session.sessionNote ?: "")
        var setVolumeSum = 0.0
        for (group in session.exerciseGroups) {
            for (line in group.sets) {
                setVolumeSum += line.volume
                lines.add(
                    listOf(
                        completedAt, SpreadsheetFormatting.csvEscape(session.title), scheduleDay,
                        session.totalVolume.toString(), SpreadsheetFormatting.csvEscape(group.exerciseName),
                        (line.setIndex + 1).toString(), line.weight.toString(), line.reps.toString(),
                        if (line.repsArePerSide) "yes" else "no", line.volume.toString(), note,
                        line.kind.rawValue, line.cardioMinutes.toString(), line.maxHeartRate.toString(),
                    ).joinToString(","),
                )
            }
        }
        lines.add(
            listOf(
                completedAt, SpreadsheetFormatting.csvEscape(session.title), scheduleDay,
                session.totalVolume.toString(), "workout_total", "", "", "", "",
                setVolumeSum.toString(), note, "", "", "",
            ).joinToString(","),
        )
    }
}

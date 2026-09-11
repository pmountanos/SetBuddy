//
//  HistorySpreadsheetExport.swift
//  Set Buddy
//

import Foundation

enum HistorySpreadsheetExport {
    private static let header: [SpreadsheetFormatting.CellValue] = [
        .text("completed_at"),
        .text("workout"),
        .text("schedule_day"),
        .text("total_volume"),
        .text("exercise"),
        .text("set_number"),
        .text("weight_kg"),
        .text("reps"),
        .text("per_side"),
        .text("set_volume"),
        .text("session_note"),
    ]

    static func buildXlsx(sessions: [HistorySessionDetail]) throws -> Data {
        var rows: [[SpreadsheetFormatting.CellValue]] = [header]
        let dateFmt = historyDateFormatter()

        for session in sessions {
            let dateStr = dateFmt.string(from: session.completedAt)
            let sched = session.scheduleDayLabel ?? ""
            let noteText = session.sessionNote ?? ""
            var daySetVolumeSum = 0.0
            for group in session.exercises {
                for line in group.sets {
                    let vol = VolumeCalculator.setVolume(
                        weight: line.weight,
                        reps: line.reps,
                        repsArePerSide: line.repsArePerSide
                    )
                    daySetVolumeSum += vol
                    rows.append([
                        .text(dateStr),
                        .text(session.workoutTitle),
                        .text(sched),
                        .number(session.totalVolume),
                        .text(group.name),
                        .number(Double(line.setNumber)),
                        .number(line.weight),
                        .number(Double(line.reps)),
                        .text(line.repsArePerSide ? "yes" : "no"),
                        .number(vol),
                        .text(noteText),
                    ])
                }
            }
            rows.append([
                .text(dateStr),
                .text(session.workoutTitle),
                .text(sched),
                .number(session.totalVolume),
                .text("workout_total"),
                .text(""),
                .text(""),
                .text(""),
                .text(""),
                .number(daySetVolumeSum),
                .text(noteText),
            ])
        }

        if rows.count == 1 {
            rows.append([
                .text(""), .text(""), .text(""), .number(0), .text(""), .number(0),
                .number(0), .number(0), .text("no"), .number(0), .text(""),
            ])
        }

        let sheetData = SpreadsheetFormatting.worksheetData(rows: rows)
        return try MinimalXlsxArchive.makeWorkbook(sheets: [
            (name: "History", worksheetPath: "xl/worksheets/sheet1.xml", worksheetData: sheetData),
        ])
    }

    static func buildCsv(sessions: [HistorySessionDetail]) throws -> Data {
        var lines: [String] = [
            "completed_at,workout,schedule_day,total_volume,exercise,set_number,weight_kg,reps,per_side,set_volume,session_note",
        ]
        let dateFmt = historyDateFormatter()

        for session in sessions {
            let dateStr = SpreadsheetFormatting.csvEscape(dateFmt.string(from: session.completedAt))
            let title = SpreadsheetFormatting.csvEscape(session.workoutTitle)
            let sched = SpreadsheetFormatting.csvEscape(session.scheduleDayLabel ?? "")
            let tv = String(session.totalVolume)
            let note = SpreadsheetFormatting.csvEscape(session.sessionNote ?? "")
            var daySetVolumeSum = 0.0
            for group in session.exercises {
                for line in group.sets {
                    let vol = VolumeCalculator.setVolume(
                        weight: line.weight,
                        reps: line.reps,
                        repsArePerSide: line.repsArePerSide
                    )
                    daySetVolumeSum += vol
                    lines.append(
                        "\(dateStr),\(title),\(sched),\(tv),\(SpreadsheetFormatting.csvEscape(group.name)),\(line.setNumber),\(line.weight),\(line.reps),\(line.repsArePerSide ? "yes" : "no"),\(vol),\(note)"
                    )
                }
            }
            lines.append(
                "\(dateStr),\(title),\(sched),\(tv),workout_total,,,,,\(daySetVolumeSum),\(note)"
            )
        }

        return SpreadsheetFormatting.csvData(lines: lines)
    }

    private static func historyDateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }
}

//
//  ProgramSpreadsheetExport.swift
//  Set Buddy
//

import Foundation

/// Exports the active program for sharing (workout tabs match `.xlsx` import layout).
enum ProgramSpreadsheetExport {
    private static let headerRow: [SpreadsheetFormatting.CellValue] = [
        .text("Exercise_Name"),
        .text("Notes"),
        .text("Per side"),
        .text("Type"),
    ]

    static func buildXlsx(program: PersistedProgram) throws -> Data {
        let workouts = program.workouts.sorted { a, b in
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return WorkoutTemplateDisplaySort.compare(a.name, b.name)
        }
        guard !workouts.isEmpty else {
            throw ExportError.noActiveProgram
        }

        var usedSheetNames = Set<String>()
        var sheets: [(name: String, worksheetPath: String, worksheetData: Data)] = []

        for workout in workouts {
            let name = uniqueSheetName(workout.name, used: &usedSheetNames)
            let path = "xl/worksheets/sheet\(sheets.count + 1).xml"
            let exercises = workout.exercises.sorted { $0.sortOrder < $1.sortOrder }
            var rows: [[SpreadsheetFormatting.CellValue]] = [headerRow]
            for ex in exercises {
                let perCell = ex.repsArePerSide ? "x" : ""
                rows.append([
                    .text(ex.name),
                    .text(ex.note ?? ""),
                    .text(perCell),
                    .text(ex.kind.rawValue),
                ])
            }
            if rows.count == 1 {
                rows.append([.text(""), .text(""), .text(""), .text("")])
            }
            let xml = SpreadsheetFormatting.worksheetData(rows: rows)
            sheets.append((name: name, worksheetPath: path, worksheetData: xml))
        }

        return try MinimalXlsxArchive.makeWorkbook(sheets: sheets)
    }

    static func buildCsv(program: PersistedProgram, calendar: Calendar) throws -> Data {
        guard !program.workouts.isEmpty else {
            throw ExportError.noActiveProgram
        }
        var lines: [String] = []
        lines.append("kind,program_name,,,")
        lines.append("program,\(SpreadsheetFormatting.csvEscape(program.name)),,,")

        let workouts = program.workouts.sorted { a, b in
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return WorkoutTemplateDisplaySort.compare(a.name, b.name)
        }
        for w in workouts {
            lines.append("workout,\(SpreadsheetFormatting.csvEscape(w.name)),,,")
            lines.append("column,sort_order,exercise_name,set_count,note,per_side,type")
            let exercises = w.exercises.sorted { $0.sortOrder < $1.sortOrder }
            for ex in exercises {
                lines.append(
                    "exercise,\(ex.sortOrder),\(SpreadsheetFormatting.csvEscape(ex.name)),\(ex.setCount),\(SpreadsheetFormatting.csvEscape(ex.note ?? "")),\(ex.repsArePerSide ? "yes" : "no"),\(ex.kind.rawValue)"
                )
            }
        }

        lines.append("kind,schedule_date,rest_or_workout,workout_name,")
        let entries = program.scheduleEntries.sorted {
            if $0.year != $1.year { return $0.year < $1.year }
            if $0.month != $1.month { return $0.month < $1.month }
            return $0.day < $1.day
        }
        for e in entries {
            var c = DateComponents()
            c.year = e.year
            c.month = e.month
            c.day = e.day
            let dateStr: String
            if let d = calendar.date(from: c) {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withFullDate]
                f.timeZone = calendar.timeZone
                dateStr = f.string(from: d)
            } else {
                dateStr = "\(e.year)-\(e.month)-\(e.day)"
            }
            if e.isRestDay {
                lines.append("schedule,\(dateStr),rest,,")
            } else if let wid = e.workoutID,
                      let wname = workouts.first(where: { $0.id == wid })?.name {
                lines.append("schedule,\(dateStr),workout,\(SpreadsheetFormatting.csvEscape(wname)),")
            } else {
                lines.append("schedule,\(dateStr),unknown,,")
            }
        }

        return SpreadsheetFormatting.csvData(lines: lines)
    }

    private static func uniqueSheetName(_ raw: String, used: inout Set<String>) -> String {
        let forbidden = CharacterSet(charactersIn: ":\\/?*[]")
        var base = String(raw.unicodeScalars.filter { !forbidden.contains($0) })
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.count > 31 {
            base = String(base.prefix(31))
        }
        if base.isEmpty {
            base = "Workout"
        }
        var candidate = base
        var i = 2
        while used.contains(candidate) {
            let suffix = " (\(i))"
            let maxLen = max(1, 31 - suffix.count)
            candidate = String(base.prefix(maxLen)) + suffix
            i += 1
        }
        used.insert(candidate)
        return candidate
    }
}

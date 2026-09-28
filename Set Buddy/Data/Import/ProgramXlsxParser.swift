//
//  ProgramXlsxParser.swift
//  Set Buddy
//

import Foundation

/// One sheet tab from the workbook, in left‑to‑right tab order (one day per sheet).
struct XlsxCycleDay: Sendable {
    let sheetName: String
    let isRestDay: Bool
    let exercises: [XlsxImportedExercise]
}

struct XlsxImportedExercise: Sendable {
    let name: String
    let note: String?
    /// Per-side flag from the mapped “per side” column (`x`, `TRUE`, `1`, `yes`, …): volume ×2.
    let repsArePerSide: Bool
    /// Strength (weight/reps) or cardio (minutes/max heart rate) — see `cardioSectionHeaderRow`.
    let kind: ExerciseKind

    init(name: String, note: String?, repsArePerSide: Bool, kind: ExerciseKind = .strength) {
        self.name = name
        self.note = note
        self.repsArePerSide = repsArePerSide
        self.kind = kind
    }
}

/// Parses `.xlsx` workbooks where each **worksheet** is one day in the rotation.
/// Workout days: **A** = exercise name (unless row‑1 headers say otherwise). **Notes** and **per‑side** columns
/// are detected from row‑1 headers (`Notes`, `Per side`, `Per Set`, …). Legacy default if no headers: **B** = note, **C** = per‑side.
/// Rest days: sheet name contains `"rest"` (case‑insensitive) **or** the sheet has no exercise rows.
/// Cardio: a row whose columns read **Minutes** / **Peak HR** (or a close synonym) marks the start of a cardio
/// section — every name below it, to the end of the sheet, becomes a cardio exercise (minutes/max heart rate
/// instead of weight/reps). A sheet can be all cardio (whole cardio day) or strength rows followed by a cardio
/// section (e.g. finishing a lift day with a cardio set) — see `ExerciseCarryoverMatcher`-adjacent tests.
enum ProgramXlsxParser {
    private static let defaultSetsPerExercise = 4

    static func parse(xlsxData: Data) throws -> [XlsxCycleDay] {
        let workbookXML = try XlsxArchiveReader.extract("xl/workbook.xml", fromXlsx: xlsxData)
        let relsXML = try XlsxArchiveReader.extract("xl/_rels/workbook.xml.rels", fromXlsx: xlsxData)
        let sharedStringsData = try? XlsxArchiveReader.extract("xl/sharedStrings.xml", fromXlsx: xlsxData)
        let sharedStrings = sharedStringsData.flatMap { parseSharedStrings(data: $0) } ?? []

        let idToTarget = WorkbookRelsParser.parse(data: relsXML)
        let sheetSpecs = WorkbookSheetsParser.parse(data: workbookXML)

        var cycle: [XlsxCycleDay] = []
        for spec in sheetSpecs {
            guard let target = idToTarget[spec.relationshipId] else { continue }
            let entryPath = "xl/" + target.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let sheetData = try XlsxArchiveReader.extract(entryPath, fromXlsx: xlsxData)
            let cells = SheetCellsParser.parse(data: sheetData, sharedStrings: sharedStrings)
            let cardioHeaderRow = cardioSectionHeaderRow(cells: cells)
            let strengthExercises = exercisesFromCells(cells, beforeRow: cardioHeaderRow)
            let cardioExercises = cardioHeaderRow.map {
                cardioExercisesFromCells(cells, afterRow: $0, nameCol: importColumnMapping(cells: cells).nameCol)
            } ?? []
            let exercises = strengthExercises + cardioExercises
            let restByName = spec.name.range(of: "rest", options: .caseInsensitive) != nil
            let isRest = restByName || exercises.isEmpty
            cycle.append(
                XlsxCycleDay(
                    sheetName: spec.name,
                    isRestDay: isRest,
                    exercises: isRest ? [] : exercises
                )
            )
        }

        guard !cycle.isEmpty else { throw ProgramImportError.workbookMissingSheets }
        return cycle
    }

    /// Default number of loggable sets per imported exercise (spreadsheet does not specify sets).
    static var defaultSetCountPerExercise: Int { defaultSetsPerExercise }

    /// Builds exercise rows from sheet cell map (`A1`-style keys). `internal` for `@testable` unit tests.
    /// - Parameter beforeRow: When given (a cardio section header was found), rows at or past it are excluded —
    ///   they belong to `cardioExercisesFromCells` instead.
    static func exercisesFromCells(_ cells: [String: String], beforeRow: Int? = nil) -> [XlsxImportedExercise] {
        let mapping = importColumnMapping(cells: cells)
        var rowNumbers = Set<Int>()
        for key in cells.keys {
            let (_, row) = parseCellAddress(key)
            rowNumbers.insert(row)
        }
        let sortedRows = rowNumbers.filter { $0 >= 1 }.sorted()
        var result: [XlsxImportedExercise] = []
        for row in sortedRows {
            if let limit = beforeRow, row >= limit { continue }
            guard let rawName = cells[address(col: mapping.nameCol, row: row)]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawName.isEmpty
            else { continue }
            if isLikelyHeaderRow(row: row, cells: cells, mapping: mapping) { continue }
            let note: String?
            if let nc = mapping.noteCol {
                let noteRaw = cells[address(col: nc, row: row)]?.trimmingCharacters(in: .whitespacesAndNewlines)
                note = (noteRaw?.isEmpty == false) ? noteRaw : nil
            } else {
                note = nil
            }
            let perKey = address(col: mapping.perSideCol, row: row)
            let perRaw = cells[perKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let perSide = spreadsheetMarksRepsPerSide(perRaw)
            result.append(XlsxImportedExercise(name: rawName, note: note, repsArePerSide: perSide))
        }
        return result
    }

    /// Row (1-based) of a **Minutes** / **Peak HR** (or synonym) header pair marking where a cardio section
    /// starts, if the sheet has one — searched left-to-right, top-to-bottom, first match wins.
    static func cardioSectionHeaderRow(cells: [String: String]) -> Int? {
        var rowNumbers = Set<Int>()
        for key in cells.keys {
            let (_, row) = parseCellAddress(key)
            rowNumbers.insert(row)
        }
        let scanCols = ["A", "B", "C", "D", "E", "F", "G", "H"]
        for row in rowNumbers.sorted() {
            for index in 0 ..< (scanCols.count - 1) {
                let raw = cells[address(col: scanCols[index], row: row)]?
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                guard headerIsMinutesColumnTitle(raw) else { continue }
                let nextRaw = cells[address(col: scanCols[index + 1], row: row)]?
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                if headerIsMaxHeartRateColumnTitle(nextRaw) {
                    return row
                }
            }
        }
        return nil
    }

    /// Cardio exercise rows after a cardio section header — name only (same name column as the strength table
    /// above it, or **A** when the sheet is cardio-only); minutes/max heart rate are logged per session, not imported.
    private static func cardioExercisesFromCells(_ cells: [String: String], afterRow: Int, nameCol: String) -> [XlsxImportedExercise] {
        var rowNumbers = Set<Int>()
        for key in cells.keys {
            let (_, row) = parseCellAddress(key)
            rowNumbers.insert(row)
        }
        let sortedRows = rowNumbers.filter { $0 > afterRow }.sorted()
        var result: [XlsxImportedExercise] = []
        for row in sortedRows {
            guard let rawName = cells[address(col: nameCol, row: row)]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawName.isEmpty
            else { continue }
            result.append(XlsxImportedExercise(name: rawName, note: nil, repsArePerSide: false, kind: .cardio))
        }
        return result
    }

    private static func headerIsMinutesColumnTitle(_ low: String) -> Bool {
        low == "minutes" || low == "min" || low == "mins"
    }

    private static func headerIsMaxHeartRateColumnTitle(_ low: String) -> Bool {
        low == "peak hr" || low == "max hr" || low == "max heart rate" || low == "peak heart rate" || low == "heart rate" || low == "hr"
    }

    private struct ImportColumnMapping {
        let nameCol: String
        let noteCol: String?
        let perSideCol: String
    }

    /// Uses row 1 headers when present; otherwise **A** / **B** / **C** (note / per‑side) legacy layout.
    private static func importColumnMapping(cells: [String: String]) -> ImportColumnMapping {
        let scan = ["A", "B", "C", "D", "E", "F", "G", "H"]
        var perSideCol: String?
        var noteCol: String?
        var nameCol: String?
        for col in scan {
            let raw = cells[address(col: col, row: 1)]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty { continue }
            let low = raw.lowercased()
            if headerIsPerSideColumnTitle(low) {
                perSideCol = col
                continue
            }
            if headerIsNotesColumnTitle(low) {
                noteCol = col
                continue
            }
            if headerIsExerciseColumnTitle(low) {
                nameCol = col
                continue
            }
        }
        let resolvedName = nameCol ?? "A"
        let resolvedPerSide = perSideCol ?? "C"
        let resolvedNote: String?
        if let n = noteCol {
            resolvedNote = n
        } else if resolvedPerSide == "B" {
            resolvedNote = (resolvedName == "C") ? "D" : "C"
        } else if resolvedPerSide == "C" {
            resolvedNote = (resolvedName == "B") ? "D" : "B"
        } else {
            resolvedNote = ["B", "C"].first { $0 != resolvedName && $0 != resolvedPerSide }
        }
        return ImportColumnMapping(nameCol: resolvedName, noteCol: resolvedNote, perSideCol: resolvedPerSide)
    }

    private static func headerIsPerSideColumnTitle(_ low: String) -> Bool {
        low == "per set" || low == "perset" || low == "per-side" || low == "per side" || low == "perside"
    }

    private static func headerIsNotesColumnTitle(_ low: String) -> Bool {
        low == "notes" || low == "note" || low.hasPrefix("note ")
    }

    private static func headerIsExerciseColumnTitle(_ low: String) -> Bool {
        low.contains("excercise")
            || (low.contains("exercise") && low.contains("name"))
            || low == "exercise"
            || low == "movement"
    }

    /// Row 1 is skipped when the name column or any common header cell looks like titles.
    private static func isLikelyHeaderRow(row: Int, cells: [String: String], mapping: ImportColumnMapping) -> Bool {
        guard row == 1 else { return false }
        let nameVal = cells[address(col: mapping.nameCol, row: 1)]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isHeaderRow(name: nameVal) { return true }
        for col in ["B", "C", "D"] {
            let h = cells[address(col: col, row: 1)]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if headerIsPerSideColumnTitle(h) || headerIsNotesColumnTitle(h) { return true }
        }
        return false
    }

    /// Column **C** markers meaning “reps are per side” (volume ×2). Accepts how Excel often stores flags.
    static func spreadsheetMarksRepsPerSide(_ cellText: String?) -> Bool {
        guard let trimmed = cellText?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return false
        }
        let lower = trimmed.lowercased()
        switch lower {
        case "x", "×", "✓", "✔", "yes", "y", "1", "true":
            return true
        default:
            return false
        }
    }

    private static func isHeaderRow(name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("excercise") || (n.contains("exercise") && n.contains("name"))
    }

    private static func address(col: String, row: Int) -> String {
        "\(col)\(row)"
    }

    private static func parseCellAddress(_ ref: String) -> (col: String, row: Int) {
        let col = String(ref.prefix { $0.isLetter })
        let rowPart = String(ref.dropFirst(col.count))
        return (col, Int(rowPart) ?? 0)
    }

    private static func parseSharedStrings(data: Data) -> [String] {
        let parser = SharedStringsParser()
        parser.parse(data: data)
        return parser.strings
    }
}

// MARK: - Workbook sheet list

private struct SheetSpec {
    let name: String
    let relationshipId: String
}

private enum WorkbookSheetsParser {
    static func parse(data: Data) -> [SheetSpec] {
        let p = Inner()
        let xml = XMLParser(data: data)
        xml.delegate = p
        guard xml.parse() else { return [] }
        return p.sheets
    }

    private final class Inner: NSObject, XMLParserDelegate {
        var sheets: [SheetSpec] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            guard localName(qName ?? elementName) == "sheet" else { return }
            guard let name = attributeDict["name"] else { return }
            let rid = attributeDict["r:id"]
                ?? attributeDict.first(where: { $0.value.hasPrefix("rId") })?.value
            guard let rid else { return }
            sheets.append(SheetSpec(name: name, relationshipId: rid))
        }
    }
}

// MARK: - workbook.xml.rels

private enum WorkbookRelsParser {
    static func parse(data: Data) -> [String: String] {
        let p = Inner()
        let xml = XMLParser(data: data)
        xml.delegate = p
        _ = xml.parse()
        return p.map
    }

    private final class Inner: NSObject, XMLParserDelegate {
        var map: [String: String] = [:]

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            guard localName(qName ?? elementName) == "Relationship" else { return }
            let id = attributeDict["Id"] ?? attributeDict["id"]
            let target = attributeDict["Target"] ?? attributeDict["target"]
            guard let id, let target else { return }
            map[id] = target
        }
    }
}

// MARK: - Shared strings

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private(set) var strings: [String] = []
    private var inSi = false
    private var chunk = ""

    func parse(data: Data) {
        let xml = XMLParser(data: data)
        xml.delegate = self
        _ = xml.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let local = localName(qName ?? elementName)
        if local == "si" {
            inSi = true
            chunk = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inSi { chunk += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let local = localName(qName ?? elementName)
        if local == "si" {
            strings.append(chunk.trimmingCharacters(in: .whitespacesAndNewlines))
            inSi = false
            chunk = ""
        }
    }
}

// MARK: - Sheet cells

private enum SheetCellsParser {
    static func parse(data: Data, sharedStrings: [String]) -> [String: String] {
        let p = Inner(sharedStrings: sharedStrings)
        let xml = XMLParser(data: data)
        xml.delegate = p
        _ = xml.parse()
        return p.cells
    }

    private final class Inner: NSObject, XMLParserDelegate {
        let sharedStrings: [String]
        var cells: [String: String] = [:]

        private var currentRef = ""
        private var currentType: String?
        private var inValue = false
        private var valueChunk = ""
        /// `t="inlineStr"` cells keep text in `<is><t>…</t></is>`, not `<v>`.
        private var inInlineIs = false
        private var inInlineT = false
        private var inlineChunk = ""

        init(sharedStrings: [String]) {
            self.sharedStrings = sharedStrings
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let local = localName(qName ?? elementName)
            if local == "c" {
                currentRef = attributeDict["r"] ?? ""
                currentType = attributeDict["t"]
                valueChunk = ""
                inlineChunk = ""
                inInlineIs = false
                inInlineT = false
            } else if local == "is", currentType == "inlineStr" {
                inInlineIs = true
                inlineChunk = ""
            } else if local == "t", inInlineIs {
                inInlineT = true
            } else if local == "v" {
                inValue = true
                valueChunk = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inValue { valueChunk += string }
            if inInlineT { inlineChunk += string }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let local = localName(qName ?? elementName)
            if local == "t", inInlineT {
                inInlineT = false
            } else if local == "is", inInlineIs {
                inInlineIs = false
            } else if local == "v" {
                inValue = false
            } else if local == "c" {
                defer {
                    currentRef = ""
                    currentType = nil
                    valueChunk = ""
                    inlineChunk = ""
                    inInlineIs = false
                    inInlineT = false
                }
                guard !currentRef.isEmpty else { return }

                let raw: String
                if currentType == "inlineStr" {
                    raw = inlineChunk.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    raw = valueChunk.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                let resolved: String
                if currentType == "s", let idx = Int(raw), sharedStrings.indices.contains(idx) {
                    resolved = sharedStrings[idx]
                } else if currentType == "b" {
                    resolved = (raw == "1") ? "TRUE" : "FALSE"
                } else {
                    resolved = raw
                }
                if !resolved.isEmpty {
                    cells[currentRef] = resolved
                }
            }
        }
    }
}

private func localName(_ qName: String) -> String {
    if let suffix = qName.split(separator: ":").last {
        return String(suffix)
    }
    return qName
}

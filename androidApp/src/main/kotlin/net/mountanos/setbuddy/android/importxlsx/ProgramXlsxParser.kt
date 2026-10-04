package net.mountanos.setbuddy.android.importxlsx

import net.mountanos.setbuddy.domain.ExerciseKind
import net.mountanos.setbuddy.domain.ImportedCycleDay
import net.mountanos.setbuddy.domain.ImportedCycleExercise
import org.xml.sax.Attributes
import org.xml.sax.helpers.DefaultHandler
import java.io.ByteArrayInputStream
import java.io.File
import javax.xml.parsers.SAXParserFactory

/**
 * Ported from `Data/Import/ProgramXlsxParser.swift`. SAX-based (mirrors Swift's `XMLParserDelegate` structure),
 * same parsing rules, same header/legacy column-mapping precedence, same rest-day and per-side-marker detection —
 * see the fidelity table in `development_plan.md`'s Android import entry.
 *
 * Cardio: a row whose columns read **Minutes** / **Peak HR** (or a close synonym) marks the start of a cardio
 * section — every name below it, to the end of the sheet, becomes a cardio exercise (minutes/max heart rate
 * instead of weight/reps). A sheet can be all cardio (whole cardio day) or strength rows followed by a cardio
 * section (e.g. finishing a lift day with a cardio set).
 */
object ProgramXlsxParser {
    const val DEFAULT_SET_COUNT_PER_EXERCISE = 4

    private data class SheetSpec(val name: String, val relationshipId: String)
    private data class ColumnMapping(val nameCol: String, val noteCol: String?, val perSideCol: String)

    fun parse(xlsxFile: File): List<ImportedCycleDay> {
        XlsxArchiveReader(xlsxFile).use { reader ->
            val workbookXml = reader.extract("xl/workbook.xml")
            val relsXml = reader.extract("xl/_rels/workbook.xml.rels")
            val sharedStringsXml = reader.extractOrNull("xl/sharedStrings.xml")

            val sheetSpecs = parseWorkbookSheets(workbookXml)
            val idToTarget = parseWorkbookRels(relsXml)
            val sharedStrings = sharedStringsXml?.let { parseSharedStrings(it) } ?: emptyList()

            val cycle = mutableListOf<ImportedCycleDay>()
            for (spec in sheetSpecs) {
                val target = idToTarget[spec.relationshipId] ?: continue
                val entryPath = "xl/" + target.trim('/')
                val sheetXml = reader.extract(entryPath)
                val cells = parseSheetCells(sheetXml, sharedStrings)
                val exercises = exercisesFromSheet(cells)
                val restByName = spec.name.contains("rest", ignoreCase = true)
                val isRest = restByName || exercises.isEmpty()
                cycle.add(ImportedCycleDay(spec.name, isRest, if (isRest) emptyList() else exercises))
            }
            if (cycle.isEmpty()) throw ProgramImportError.WorkbookMissingSheets
            return cycle
        }
    }

    // -- Column mapping ------------------------------------------------------

    private val headerScanColumns = listOf("A", "B", "C", "D", "E", "F", "G", "H")

    private fun headerIsPerSideColumnTitle(low: String): Boolean =
        low == "per set" || low == "perset" || low == "per-side" || low == "per side" || low == "perside"

    private fun headerIsNotesColumnTitle(low: String): Boolean =
        low == "notes" || low == "note" || low.startsWith("note ")

    private fun headerIsExerciseColumnTitle(low: String): Boolean =
        low.contains("excercise") || (low.contains("exercise") && low.contains("name")) ||
            low == "exercise" || low == "movement"

    private fun importColumnMapping(cells: Map<String, String>): ColumnMapping {
        var nameCol: String? = null
        var noteCol: String? = null
        var perSideCol: String? = null
        for (col in headerScanColumns) {
            val raw = cells["${col}1"]?.trim()
            if (raw.isNullOrEmpty()) continue
            val low = raw.lowercase()
            when {
                headerIsPerSideColumnTitle(low) -> if (perSideCol == null) perSideCol = col
                headerIsNotesColumnTitle(low) -> if (noteCol == null) noteCol = col
                headerIsExerciseColumnTitle(low) -> if (nameCol == null) nameCol = col
            }
        }
        val resolvedName = nameCol ?: "A"
        val resolvedPerSide = perSideCol ?: "C"
        val resolvedNote: String? = when {
            noteCol != null -> noteCol
            resolvedPerSide == "B" -> if (resolvedName == "C") "D" else "C"
            resolvedPerSide == "C" -> if (resolvedName == "B") "D" else "B"
            else -> listOf("B", "C").firstOrNull { it != resolvedName && it != resolvedPerSide }
        }
        return ColumnMapping(resolvedName, resolvedNote, resolvedPerSide)
    }

    private fun isHeaderRowName(name: String): Boolean {
        val n = name.lowercase()
        return n.contains("excercise") || (n.contains("exercise") && n.contains("name"))
    }

    private fun isLikelyHeaderRow(cells: Map<String, String>, mapping: ColumnMapping): Boolean {
        val nameVal = cells["${mapping.nameCol}1"]?.trim() ?: ""
        if (isHeaderRowName(nameVal)) return true
        for (col in listOf("B", "C", "D")) {
            val h = cells["${col}1"]?.trim()?.lowercase() ?: ""
            if (headerIsPerSideColumnTitle(h) || headerIsNotesColumnTitle(h)) return true
        }
        return false
    }

    /** Marker set is exact-equality (not substring), case-insensitive, trimmed. */
    fun spreadsheetMarksRepsPerSide(cellText: String?): Boolean {
        val trimmed = cellText?.trim()
        if (trimmed.isNullOrEmpty()) return false
        return when (trimmed.lowercase()) {
            "x", "×", "✓", "✔", "yes", "y", "1", "true" -> true
            else -> false
        }
    }

    /** Strength rows, then (if the sheet has a cardio section header) the cardio rows below it. */
    internal fun exercisesFromSheet(cells: Map<String, String>): List<ImportedCycleExercise> {
        val cardioHeaderRow = cardioSectionHeaderRow(cells)
        val strength = exercisesFromCells(cells, beforeRow = cardioHeaderRow)
        val cardio = cardioHeaderRow?.let { cardioExercisesFromCells(cells, afterRow = it) } ?: emptyList()
        return strength + cardio
    }

    /** @param beforeRow when given (a cardio section header was found), rows at or past it are excluded — they belong to [cardioExercisesFromCells] instead. */
    private fun exercisesFromCells(cells: Map<String, String>, beforeRow: Int? = null): List<ImportedCycleExercise> {
        val mapping = importColumnMapping(cells)
        val rowNumbers = cells.keys.map { parseCellAddress(it).second }.filter { it >= 1 }.toSortedSet()
        val result = mutableListOf<ImportedCycleExercise>()
        for (row in rowNumbers) {
            if (beforeRow != null && row >= beforeRow) continue
            val rawName = cells["${mapping.nameCol}$row"]?.trim()
            if (rawName.isNullOrEmpty()) continue
            if (row == 1 && isLikelyHeaderRow(cells, mapping)) continue
            val note = mapping.noteCol?.let { nc -> cells["$nc$row"]?.trim()?.takeIf { it.isNotEmpty() } }
            val perRaw = cells["${mapping.perSideCol}$row"]?.trim()
            result.add(ImportedCycleExercise(rawName, note, spreadsheetMarksRepsPerSide(perRaw)))
        }
        return result
    }

    /**
     * Row (1-based) of a **Minutes** / **Peak HR** (or synonym) header pair marking where a cardio section starts,
     * if the sheet has one — searched left-to-right, top-to-bottom, first match wins.
     */
    internal fun cardioSectionHeaderRow(cells: Map<String, String>): Int? {
        val rowNumbers = cells.keys.map { parseCellAddress(it).second }.toSortedSet()
        for (row in rowNumbers) {
            for (index in 0 until headerScanColumns.size - 1) {
                val raw = cells["${headerScanColumns[index]}$row"]?.trim()?.lowercase() ?: ""
                if (!headerIsMinutesColumnTitle(raw)) continue
                val nextRaw = cells["${headerScanColumns[index + 1]}$row"]?.trim()?.lowercase() ?: ""
                if (headerIsMaxHeartRateColumnTitle(nextRaw)) return row
            }
        }
        return null
    }

    /**
     * Cardio exercise rows after a cardio section header — name only (same name column as the strength table
     * above it, or **A** when the sheet is cardio-only); minutes/max heart rate are logged per session, not imported.
     */
    private fun cardioExercisesFromCells(cells: Map<String, String>, afterRow: Int): List<ImportedCycleExercise> {
        val nameCol = importColumnMapping(cells).nameCol
        val rowNumbers = cells.keys.map { parseCellAddress(it).second }.filter { it > afterRow }.toSortedSet()
        return rowNumbers.mapNotNull { row ->
            val rawName = cells["$nameCol$row"]?.trim()
            if (rawName.isNullOrEmpty()) null else ImportedCycleExercise(rawName, kind = ExerciseKind.Cardio)
        }
    }

    private fun headerIsMinutesColumnTitle(low: String): Boolean =
        low == "minutes" || low == "min" || low == "mins"

    private fun headerIsMaxHeartRateColumnTitle(low: String): Boolean =
        low == "peak hr" || low == "max hr" || low == "max heart rate" || low == "peak heart rate" ||
            low == "heart rate" || low == "hr"

    private fun parseCellAddress(ref: String): Pair<String, Int> {
        val colChars = ref.takeWhile { it.isLetter() }
        val rowDigits = ref.dropWhile { it.isLetter() }
        return colChars to (rowDigits.toIntOrNull() ?: 0)
    }

    // -- XML (SAX) -------------------------------------------------------------

    private fun localNameOf(qName: String): String = qName.substringAfterLast(':')

    private fun saxParse(xml: ByteArray, handler: DefaultHandler) {
        try {
            SAXParserFactory.newInstance().newSAXParser().parse(ByteArrayInputStream(xml), handler)
        } catch (e: Exception) {
            // Matches the Swift parsers' silent-empty-result-on-parse-failure behavior.
        }
    }

    private fun parseWorkbookSheets(xml: ByteArray): List<SheetSpec> {
        val specs = mutableListOf<SheetSpec>()
        saxParse(xml, object : DefaultHandler() {
            override fun startElement(uri: String?, localName: String?, qName: String?, attributes: Attributes?) {
                if (localNameOf(qName ?: return) != "sheet") return
                val attrs = attributes ?: return
                val name = attrs.getValue("name") ?: return
                var rId = attrs.getValue("r:id")
                if (rId == null) {
                    for (i in 0 until attrs.length) {
                        val v = attrs.getValue(i)
                        if (v != null && v.startsWith("rId")) {
                            rId = v
                            break
                        }
                    }
                }
                if (rId != null) specs.add(SheetSpec(name, rId))
            }
        })
        return specs
    }

    private fun parseWorkbookRels(xml: ByteArray): Map<String, String> {
        val idToTarget = mutableMapOf<String, String>()
        saxParse(xml, object : DefaultHandler() {
            override fun startElement(uri: String?, localName: String?, qName: String?, attributes: Attributes?) {
                if (localNameOf(qName ?: return) != "Relationship") return
                val attrs = attributes ?: return
                val id = attrs.getValue("Id") ?: attrs.getValue("id") ?: return
                val target = attrs.getValue("Target") ?: attrs.getValue("target") ?: return
                idToTarget[id] = target
            }
        })
        return idToTarget
    }

    private fun parseSharedStrings(xml: ByteArray): List<String> {
        val strings = mutableListOf<String>()
        var inSi = false
        val chunk = StringBuilder()
        saxParse(xml, object : DefaultHandler() {
            override fun startElement(uri: String?, localName: String?, qName: String?, attributes: Attributes?) {
                if (localNameOf(qName ?: return) == "si") {
                    inSi = true
                    chunk.clear()
                }
            }

            override fun characters(ch: CharArray, start: Int, length: Int) {
                if (inSi) chunk.append(ch, start, length)
            }

            override fun endElement(uri: String?, localName: String?, qName: String?) {
                if (localNameOf(qName ?: return) == "si") {
                    strings.add(chunk.toString().trim())
                    inSi = false
                    chunk.clear()
                }
            }
        })
        return strings
    }

    private fun parseSheetCells(xml: ByteArray, sharedStrings: List<String>): Map<String, String> {
        val cells = mutableMapOf<String, String>()
        var currentRef: String? = null
        var currentType: String? = null
        var inValue = false
        var inInlineText = false
        val valueChunk = StringBuilder()
        val inlineChunk = StringBuilder()

        fun resolveCellText(): String = when (currentType) {
            "s" -> {
                val idx = valueChunk.toString().trim().toIntOrNull()
                if (idx != null && idx in sharedStrings.indices) sharedStrings[idx] else valueChunk.toString().trim()
            }
            "b" -> if (valueChunk.toString().trim() == "1") "TRUE" else "FALSE"
            "inlineStr" -> inlineChunk.toString().trim()
            else -> valueChunk.toString().trim()
        }

        saxParse(xml, object : DefaultHandler() {
            override fun startElement(uri: String?, localName: String?, qName: String?, attributes: Attributes?) {
                when (localNameOf(qName ?: return)) {
                    "c" -> {
                        currentRef = attributes?.getValue("r")
                        currentType = attributes?.getValue("t")
                        valueChunk.clear()
                        inlineChunk.clear()
                    }
                    "v" -> {
                        inValue = true
                        valueChunk.clear()
                    }
                    "t" -> if (currentType == "inlineStr") {
                        inInlineText = true
                        inlineChunk.clear()
                    }
                }
            }

            override fun characters(ch: CharArray, start: Int, length: Int) {
                if (inValue) valueChunk.append(ch, start, length)
                if (inInlineText) inlineChunk.append(ch, start, length)
            }

            override fun endElement(uri: String?, localName: String?, qName: String?) {
                when (localNameOf(qName ?: return)) {
                    "v" -> inValue = false
                    "t" -> inInlineText = false
                    "c" -> {
                        val ref = currentRef
                        if (ref != null) {
                            val resolved = resolveCellText()
                            if (resolved.isNotEmpty()) cells[ref] = resolved
                        }
                        currentRef = null
                        currentType = null
                    }
                }
            }
        })
        return cells
    }
}

package net.mountanos.setbuddy.android.export

import kotlin.math.abs
import kotlin.math.floor

/** Ported from `Data/Export/SpreadsheetFormatting.swift`. */
sealed class Cell {
    data class Text(val value: String) : Cell()
    data class Number(val value: Double) : Cell()
}

object SpreadsheetFormatting {
    /** 0-based index -> Excel column letters ("A", ..., "Z", "AA", ...). */
    fun columnLetters(index: Int): String {
        var n = index
        val sb = StringBuilder()
        while (true) {
            sb.insert(0, ('A' + (n % 26)))
            n = n / 26 - 1
            if (n < 0) break
        }
        return sb.toString()
    }

    /** [row] is 1-based. */
    fun cellRef(row: Int, col: Int): String = "${columnLetters(col)}$row"

    fun escapeXmlText(s: String): String =
        s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

    fun csvEscape(s: String): String =
        if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
            "\"" + s.replace("\"", "\"\"") + "\""
        } else {
            s
        }

    /** UTF-8 BOM + `\n`-joined lines. */
    fun csvBytes(lines: List<String>): ByteArray {
        val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
        return bom + lines.joinToString("\n").toByteArray(Charsets.UTF_8)
    }

    /** Builds one worksheet XML part body from a grid of rows (1-indexed internally). */
    fun worksheetXml(rows: List<List<Cell>>): String {
        val sb = StringBuilder()
        sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
        sb.append("<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">\n")
        sb.append("<sheetData>\n")
        rows.forEachIndexed { rowIndex, row ->
            val r = rowIndex + 1
            sb.append("<row r=\"$r\">")
            row.forEachIndexed { colIndex, cell ->
                val ref = cellRef(r, colIndex)
                when (cell) {
                    is Cell.Text -> sb.append("<c r=\"$ref\" t=\"inlineStr\"><is><t>${escapeXmlText(cell.value)}</t></is></c>")
                    is Cell.Number -> {
                        val n = cell.value
                        val text = if (n == floor(n) && abs(n) < 1e15) n.toLong().toString() else n.toString()
                        sb.append("<c r=\"$ref\"><v>$text</v></c>")
                    }
                }
            }
            sb.append("</row>\n")
        }
        sb.append("</sheetData></worksheet>")
        return sb.toString()
    }
}

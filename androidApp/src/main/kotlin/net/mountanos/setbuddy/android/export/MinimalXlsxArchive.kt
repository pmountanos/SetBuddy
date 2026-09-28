package net.mountanos.setbuddy.android.export

import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Ported from `Data/Export/MinimalXlsxArchive.swift`. Uses standard DEFLATE compression (the iOS writer uses
 * STORED/no-compression) — a valid zip reads identically to any OOXML consumer either way, so this is a safe
 * simplification, not a format requirement.
 */
object MinimalXlsxArchive {
    data class Sheet(val name: String, val xml: String)

    fun makeWorkbook(sheets: List<Sheet>): ByteArray {
        val baos = ByteArrayOutputStream()
        ZipOutputStream(baos).use { zip ->
            fun writeEntry(path: String, content: String) {
                zip.putNextEntry(ZipEntry(path))
                zip.write(content.toByteArray(Charsets.UTF_8))
                zip.closeEntry()
            }

            writeEntry("[Content_Types].xml", contentTypes(sheets.size))
            writeEntry("_rels/.rels", rootRels)
            writeEntry("xl/_rels/workbook.xml.rels", workbookRels(sheets.size))
            writeEntry("xl/workbook.xml", workbookXml(sheets.map { it.name }))
            sheets.forEachIndexed { index, sheet ->
                writeEntry("xl/worksheets/sheet${index + 1}.xml", sheet.xml)
            }
        }
        return baos.toByteArray()
    }

    private fun contentTypes(sheetCount: Int): String {
        val overrides = (1..sheetCount).joinToString("\n") { n ->
            "<Override PartName=\"/xl/worksheets/sheet$n.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
$overrides
</Types>"""
    }

    private val rootRels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>"""

    private fun workbookRels(sheetCount: Int): String {
        val rels = (1..sheetCount).joinToString("\n") { n ->
            "<Relationship Id=\"rId$n\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet$n.xml\"/>"
        }
        return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
$rels
</Relationships>"""
    }

    private fun workbookXml(sheetNames: List<String>): String {
        val sheetElements = sheetNames.mapIndexed { index, name ->
            "<sheet name=\"${SpreadsheetFormatting.escapeXmlText(name)}\" sheetId=\"${index + 1}\" r:id=\"rId${index + 1}\"/>"
        }.joinToString("")
        return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>
$sheetElements
</sheets>
</workbook>"""
    }
}

//
//  MinimalXlsxArchive.swift
//  Set Buddy
//

import Foundation
import ZIPFoundation

/// Builds a minimal OOXML `.xlsx` (ZIP of XML parts) for small exports.
enum MinimalXlsxArchive {
    static func zip(entries: [(path: String, data: Data)]) throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("setbuddy-xlsx-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        guard let archive = Archive(url: url, accessMode: .create) else {
            throw ExportError.couldNotCreateArchive
        }

        for entry in entries {
            let data = entry.data
            let size = UInt32(clamping: data.count)
            try archive.addEntry(
                with: entry.path,
                type: .file,
                uncompressedSize: size,
                compressionMethod: .none
            ) { offset, chunkSize in
                let start = Int(offset)
                let end = min(start + chunkSize, data.count)
                return data.subdata(in: start ..< end)
            }
        }

        return try Data(contentsOf: url)
    }

    /// Assembles a multi-sheet workbook from worksheet XML blobs (paths like `xl/worksheets/sheet1.xml`).
    static func makeWorkbook(
        sheets: [(name: String, worksheetPath: String, worksheetData: Data)]
    ) throws -> Data {
        var entries: [(String, Data)] = []

        entries.append(("[Content_Types].xml", Data(contentTypes(sheetCount: sheets.count).utf8)))
        entries.append(("_rels/.rels", Data(rootRels.utf8)))

        var workbookSheetElements: [String] = []
        var relsLines: [String] = []
        relsLines.append(
            #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        )
        relsLines.append(
            #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        )

        for (i, sheet) in sheets.enumerated() {
            let sheetId = i + 1
            let rid = "rId\(sheetId)"
            let pathInZip = sheet.worksheetPath
            entries.append((pathInZip, sheet.worksheetData))
            let escapedName = SpreadsheetFormatting.escapeXmlText(sheet.name)
            workbookSheetElements.append(
                "<sheet name=\"\(escapedName)\" sheetId=\"\(sheetId)\" r:id=\"\(rid)\"/>"
            )
            relsLines.append(
                "<Relationship Id=\"\(rid)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(sheetId).xml\"/>"
            )
        }

        relsLines.append("</Relationships>")
        entries.append(("xl/_rels/workbook.xml.rels", Data(relsLines.joined(separator: "\n").utf8)))

        let workbookXml = workbookXML(sheetElements: workbookSheetElements.joined())
        entries.append(("xl/workbook.xml", Data(workbookXml.utf8)))

        return try zip(entries: entries)
    }

    private static func contentTypes(sheetCount: Int) -> String {
        var overrides = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        """
        for i in 1 ... sheetCount {
            overrides += """
            <Override PartName="/xl/worksheets/sheet\(i).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
            """
        }
        overrides += "</Types>"
        return overrides
    }

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static func workbookXML(sheetElements: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>
        \(sheetElements)
        </sheets>
        </workbook>
        """
    }
}

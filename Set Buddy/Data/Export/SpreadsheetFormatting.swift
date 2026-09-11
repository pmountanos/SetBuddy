//
//  SpreadsheetFormatting.swift
//  Set Buddy
//

import Foundation

enum SpreadsheetFormatting {
    /// Excel column letters for zero-based column index (0 → A).
    static func columnLetters(_ index: Int) -> String {
        var n = index + 1
        var letters = ""
        while n > 0 {
            let rem = (n - 1) % 26
            letters = String(Character(UnicodeScalar(65 + rem)!)) + letters
            n = (n - 1) / 26
        }
        return letters
    }

    static func cellRef(row: Int, col: Int) -> String {
        "\(columnLetters(col))\(row)"
    }

    static func escapeXmlText(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Quotes a CSV field when it contains a comma, quote, or newline (doubling embedded quotes).
    static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    /// UTF-8 CSV with a leading BOM (Excel-on-Windows encoding hint) and `\n`-joined rows.
    static func csvData(lines: [String]) -> Data {
        let bom = Data([0xEF, 0xBB, 0xBF])
        let body = lines.joined(separator: "\n").data(using: .utf8) ?? Data()
        return bom + body
    }

    enum CellValue {
        case text(String)
        case number(Double)
    }

    /// Minimal worksheet XML (inline strings + numeric cells).
    static func worksheetData(rows: [[CellValue]]) -> Data {
        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#)
        lines.append(
            #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#
        )
        lines.append("<sheetData>")
        for (ri, row) in rows.enumerated() {
            let r = ri + 1
            var rowXml = "<row r=\"\(r)\">"
            for (ci, cell) in row.enumerated() {
                let ref = cellRef(row: r, col: ci)
                switch cell {
                case .text(let t):
                    let esc = escapeXmlText(t)
                    rowXml += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(esc)</t></is></c>"
                case .number(let n):
                    if n == floor(n) && abs(n) < 1e15 {
                        rowXml += "<c r=\"\(ref)\"><v>\(Int(n))</v></c>"
                    } else {
                        rowXml += "<c r=\"\(ref)\"><v>\(n)</v></c>"
                    }
                }
            }
            rowXml += "</row>"
            lines.append(rowXml)
        }
        lines.append("</sheetData></worksheet>")
        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }
}

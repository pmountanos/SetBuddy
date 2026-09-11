//
//  XlsxArchiveReader.swift
//  Set Buddy
//

import Foundation
import ZIPFoundation

enum XlsxArchiveReader {
    static func extract(_ entryPath: String, fromXlsx xlsx: Data) throws -> Data {
        let archive: Archive
        do {
            archive = try Archive(data: xlsx, accessMode: .read)
        } catch {
            throw ProgramImportError.invalidXlsxArchive
        }
        let normalized = entryPath.replacingOccurrences(of: "\\", with: "/")
        guard let entry = archive.first(where: {
            $0.path == normalized || $0.path.lowercased() == normalized.lowercased()
        }) else {
            throw ProgramImportError.missingZipEntry(entryPath)
        }
        var result = Data()
        _ = try archive.extract(entry, consumer: { chunk in result.append(chunk) })
        return result
    }
}

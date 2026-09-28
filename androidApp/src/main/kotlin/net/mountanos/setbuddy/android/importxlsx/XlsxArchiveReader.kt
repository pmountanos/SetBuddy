package net.mountanos.setbuddy.android.importxlsx

import java.io.File
import java.util.zip.ZipFile

/**
 * Ported from `Data/Import/XlsxArchiveReader.swift`. `ZipFile` needs a real [File] (unlike ZIPFoundation's
 * in-memory `Data` archive), so the caller copies the picked document to a temp file once and reuses it across
 * every `extract` call — each call still re-opens/re-scans that file fresh, matching the Swift version's
 * stateless, no-cached-archive contract.
 */
class XlsxArchiveReader(private val file: File) : AutoCloseable {
    private val zip: ZipFile = try {
        ZipFile(file)
    } catch (e: Exception) {
        throw ProgramImportError.InvalidXlsxArchive
    }

    fun extract(entryPath: String): ByteArray {
        val normalized = entryPath.replace('\\', '/')
        val entry = zip.getEntry(normalized)
            ?: zip.entries().asSequence().firstOrNull { it.name.equals(normalized, ignoreCase = true) }
            ?: throw ProgramImportError.MissingZipEntry(entryPath)
        return zip.getInputStream(entry).use { it.readBytes() }
    }

    /** As iOS's `try?` — missing entry (or any read failure) resolves to `null` instead of throwing. */
    fun extractOrNull(entryPath: String): ByteArray? =
        try {
            extract(entryPath)
        } catch (e: ProgramImportError) {
            null
        }

    override fun close() {
        zip.close()
    }
}

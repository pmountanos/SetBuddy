package net.mountanos.setbuddy.android.export

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class ExportedFile(val file: File, val mimeType: String)

/** Ported from `ExportViewModel.swift`'s `writeExportFile` — tries xlsx, falls back to CSV on any failure. */
object ExportFileWriter {
    private fun stamp(): String = SimpleDateFormat("yyyy-MM-dd_HHmmss", Locale.US).format(Date())

    private data class Attempt(val bytes: ByteArray, val ext: String, val mime: String)

    fun write(context: Context, prefix: String, xlsxBytes: () -> ByteArray, csvBytes: () -> ByteArray): ExportedFile {
        val attempt = try {
            Attempt(xlsxBytes(), "xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        } catch (e: Exception) {
            Attempt(csvBytes(), "csv", "text/csv")
        }
        val file = File(context.cacheDir, "${prefix}_${stamp()}.${attempt.ext}")
        file.writeBytes(attempt.bytes)
        return ExportedFile(file, attempt.mime)
    }
}

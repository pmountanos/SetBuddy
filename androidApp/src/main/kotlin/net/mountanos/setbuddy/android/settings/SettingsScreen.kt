package net.mountanos.setbuddy.android.settings

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings as AndroidSettings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import net.mountanos.setbuddy.android.BuildConfig
import net.mountanos.setbuddy.android.export.ExportFileWriter
import net.mountanos.setbuddy.android.export.HistorySpreadsheetExport
import net.mountanos.setbuddy.android.export.ProgramSpreadsheetExport
import net.mountanos.setbuddy.android.importxlsx.ImportedProgramDisplayNaming
import net.mountanos.setbuddy.android.importxlsx.ProgramImportError
import net.mountanos.setbuddy.android.importxlsx.ProgramXlsxImporter
import net.mountanos.setbuddy.android.importxlsx.ProgramXlsxParser
import net.mountanos.setbuddy.android.notifications.DailyNotificationScheduler
import net.mountanos.setbuddy.android.notifications.NotificationPrefs
import net.mountanos.setbuddy.android.notifications.NotificationSettings
import net.mountanos.setbuddy.domain.CalendarDate
import net.mountanos.setbuddy.domain.ExerciseCarryoverMatcher
import net.mountanos.setbuddy.domain.ImportExerciseRef
import net.mountanos.setbuddy.domain.ImportedCycleDay
import net.mountanos.setbuddy.shared.data.HistoryRepository
import net.mountanos.setbuddy.shared.data.ProgramOutlineRepository
import net.mountanos.setbuddy.shared.data.ProgramRepository
import java.io.File
import kotlin.uuid.Uuid

private data class StagedImport(
    val cycle: List<ImportedCycleDay>,
    val programName: String,
    val cycleDayLabels: List<String>,
    val autoCarryover: Map<ImportExerciseRef, Uuid>,
    val suggestions: List<ExerciseCarryoverMatcher.Suggestion>,
)

private const val HOW_IT_WORKS_TEXT = "Set Buddy uses one active training program. Build it on the Program tab " +
    "(Start over there resets to a fresh starter), or import a spreadsheet here. Replacing the program clears " +
    "in-progress workouts; completed sessions remain in History."

private const val NOTIFICATIONS_FOOTER = "One reminder per day at the time you choose. The message matches your " +
    "program: workout day vs rest day. Turn off the toggle to stop scheduling reminders (already delivered " +
    "notifications are unchanged)."

private const val PROGRAM_SECTION_FOOTER = "“Upcoming schedule list” controls how many days appear on " +
    "the Program tab. Pick a file, then choose which day in the workbook is next and the calendar day that maps " +
    "to it. The schedule continues in worksheet tab order. Row 1 can name columns: exercise, Notes, and Per side " +
    "(order flexible). In each row, mark per side with x, ✓, yes, 1, or TRUE where that column's header says " +
    "Per side / Per set. If there are no headers, the app assumes B = note and C = per side. Rest: empty sheet " +
    "or a name containing “Rest”. Import clears any in-progress workout. Note: Total work history " +
    "(completed sessions and volume) is kept when you import a new program."

private const val EXPORT_FOOTER = "Spreadsheet exports use the date and time in the file name " +
    "(Set_Buddy_Program_… or Set_Buddy_History_…). Program workbooks use one sheet per workout with " +
    "the same columns as import (Exercise_Name, Notes, Per side). The CSV program export also includes the " +
    "calendar schedule. History includes every completed set. Prefer .xlsx; if that fails, a .csv file is " +
    "offered instead."

@Composable
fun SettingsScreen(
    programRepository: ProgramRepository,
    outlineRepository: ProgramOutlineRepository,
    historyRepository: HistoryRepository,
    notificationScheduler: DailyNotificationScheduler,
    programXlsxImporter: ProgramXlsxImporter,
) {
    val context = LocalContext.current
    var prefs by remember { mutableStateOf(NotificationSettings.load(context)) }
    var scheduleDays by remember { mutableIntStateOf(ProgramSchedulePreviewDaysSetting.load(context)) }
    var hasRequestedNotificationPermission by remember {
        mutableStateOf(NotificationPermissionAsked.load(context))
    }

    var staged by remember { mutableStateOf<StagedImport?>(null) }
    var importMessage by remember { mutableStateOf<String?>(null) }
    var importError by remember { mutableStateOf<String?>(null) }
    var exportError by remember { mutableStateOf<String?>(null) }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        NotificationPermissionAsked.save(context, true)
        hasRequestedNotificationPermission = true
        if (granted) notificationScheduler.requestReschedule()
    }

    fun updatePrefs(newPrefs: NotificationPrefs) {
        prefs = newPrefs
        NotificationSettings.save(context, newPrefs)
        notificationScheduler.requestReschedule()
    }

    val pickerLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        importMessage = null
        importError = null
        try {
            val file = copyUriToCacheFile(context, uri)
            val cycle = ProgramXlsxParser.parse(file)
            val fileTitle = (displayNameOf(context, uri) ?: file.name)
                .removeSuffix(".xlsx").removeSuffix(".XLSX")
            val resolvedName = ImportedProgramDisplayNaming.programName(fileTitle)
            val labels = cycle.mapIndexed { i, day ->
                "${i + 1}. ${day.sheetName}" + if (day.isRestDay) " — Rest" else ""
            }
            val matchResult = ExerciseCarryoverMatcher.match(programRepository.existingExercisesForCarryover(), cycle)
            staged = StagedImport(cycle, resolvedName, labels, matchResult.autoCarryover, matchResult.suggestions)
        } catch (e: ProgramImportError) {
            importError = e.message
        } catch (e: Exception) {
            importError = "Couldn't read that file."
        }
    }

    fun shareFile(file: File, mimeType: String) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, file.name))
    }

    fun exportProgram() {
        exportError = null
        try {
            val outline = outlineRepository.activeProgramOutline() ?: throw IllegalStateException(
                "There is no program to export. Create or import one on the Program tab.",
            )
            val schedule = programRepository.activeProgram()?.let { programRepository.calendarSchedule(it) }
                ?: net.mountanos.setbuddy.domain.ProgramCalendarSchedule()
            val exported = ExportFileWriter.write(
                context, "Set_Buddy_Program",
                xlsxBytes = { ProgramSpreadsheetExport.buildXlsx(outline) },
                csvBytes = { ProgramSpreadsheetExport.buildCsv(outline, schedule) },
            )
            shareFile(exported.file, exported.mimeType)
        } catch (e: Exception) {
            exportError = e.message ?: "Could not create the spreadsheet file."
        }
    }

    fun exportHistory() {
        exportError = null
        try {
            val sessions = historyRepository.allCompletedSessionDetails()
            val exported = ExportFileWriter.write(
                context, "Set_Buddy_History",
                xlsxBytes = { HistorySpreadsheetExport.buildXlsx(sessions) },
                csvBytes = { HistorySpreadsheetExport.buildCsv(sessions) },
            )
            shareFile(exported.file, exported.mimeType)
        } catch (e: Exception) {
            exportError = e.message ?: "Could not create the spreadsheet file."
        }
    }

    val notificationsAllowed = NotificationManagerCompat.from(context).areNotificationsEnabled()

    LazyColumn(modifier = Modifier.fillMaxSize().padding(24.dp)) {
        item {
            Text("How it works", style = MaterialTheme.typography.titleMedium)
            Text(
                HOW_IT_WORKS_TEXT,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 4.dp),
            )

            HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

            Text("Notifications", style = MaterialTheme.typography.titleMedium)
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("Daily plan reminder")
                Switch(
                    checked = prefs.dailyRemindersEnabled,
                    onCheckedChange = { enabled ->
                        updatePrefs(prefs.copy(dailyRemindersEnabled = enabled))
                        if (enabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !notificationsAllowed) {
                            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        }
                    },
                )
            }
            if (prefs.dailyRemindersEnabled) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 8.dp)) {
                    OutlinedTextField(
                        value = prefs.hour.toString(),
                        onValueChange = { it.toIntOrNull()?.let { h -> if (h in 0..23) updatePrefs(prefs.copy(hour = h)) } },
                        label = { Text("Hour (0-23)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = prefs.minute.toString(),
                        onValueChange = { it.toIntOrNull()?.let { m -> if (m in 0..59) updatePrefs(prefs.copy(minute = m)) } },
                        label = { Text("Minute (0-59)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            if (!notificationsAllowed) {
                if (!hasRequestedNotificationPermission && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    OutlinedButton(
                        onClick = { permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) },
                        modifier = Modifier.padding(top = 8.dp),
                    ) { Text("Allow notifications") }
                    Text(
                        "Allow notifications so Set Buddy can remind you on workout and rest days.",
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                } else {
                    OutlinedButton(
                        onClick = {
                            val intent = Intent(AndroidSettings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(AndroidSettings.EXTRA_APP_PACKAGE, context.packageName)
                            context.startActivity(intent)
                        },
                        modifier = Modifier.padding(top = 8.dp),
                    ) { Text("Open system settings") }
                    Text(
                        "Notifications are turned off for Set Buddy. Use “Open system settings” to enable alerts.",
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
            } else {
                Text(
                    "System permission is on. Reminders use your chosen time when the toggle above is on.",
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            Text(
                NOTIFICATIONS_FOOTER,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 8.dp),
            )

            HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

            Text("Program", style = MaterialTheme.typography.titleMedium)
            Text("Upcoming schedule list", style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 4.dp)) {
                ProgramSchedulePreviewDaysSetting.choices.forEach { days ->
                    val selected = days == scheduleDays
                    if (selected) {
                        Button(onClick = {}) { Text("$days days") }
                    } else {
                        OutlinedButton(onClick = {
                            scheduleDays = days
                            ProgramSchedulePreviewDaysSetting.save(context, days)
                        }) { Text("$days days") }
                    }
                }
            }
            OutlinedButton(
                onClick = { pickerLauncher.launch(arrayOf("*/*")) },
                modifier = Modifier.padding(top = 12.dp),
            ) { Text("Import program (.xlsx)") }
            importMessage?.let { Text(it, modifier = Modifier.padding(top = 8.dp)) }
            importError?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp)) }
            Text(
                PROGRAM_SECTION_FOOTER,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 8.dp),
            )

            HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

            Text("Export", style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 8.dp)) {
                OutlinedButton(onClick = { exportProgram() }) { Text("Export program") }
                OutlinedButton(onClick = { exportHistory() }) { Text("Export workout history") }
            }
            exportError?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp)) }
            Text(
                EXPORT_FOOTER,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 8.dp),
            )

            HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

            Text(
                "Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(modifier = Modifier.height(24.dp))
        }
    }

    val s = staged
    if (s != null) {
        ImportStagingDialog(
            staged = s,
            onDismiss = { staged = null },
            onConfirm = { cycleStartIndex, startDate, confirmedSuggestionIds ->
                val carryover = s.autoCarryover.toMutableMap()
                for (suggestion in s.suggestions) {
                    if (suggestion.id in confirmedSuggestionIds) {
                        carryover[suggestion.newExercise] = suggestion.oldExerciseId
                    }
                }
                try {
                    programXlsxImporter.importReplacingStore(
                        cycle = s.cycle,
                        programName = s.programName,
                        startDate = startDate,
                        cycleStartIndex = cycleStartIndex,
                        exerciseCarryover = carryover,
                    )
                    notificationScheduler.requestReschedule()
                    importMessage = "Imported \"${s.programName}\"." +
                        if (carryover.isNotEmpty()) " Reference weights carried over for ${carryover.size} matching exercise(s)." else ""
                    importError = null
                } catch (e: Exception) {
                    importError = e.message ?: "Import failed."
                }
                staged = null
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ImportStagingDialog(
    staged: StagedImport,
    onDismiss: () -> Unit,
    onConfirm: (cycleStartIndex: Int, startDate: CalendarDate, confirmedSuggestionIds: Set<Uuid>) -> Unit,
) {
    var selectedCycleDayIndex by remember { mutableIntStateOf(0) }
    var cycleDayMenuExpanded by remember { mutableStateOf(false) }
    var confirmedSuggestionIds by remember {
        mutableStateOf(staged.suggestions.map { it.id }.toSet())
    }
    var showDatePicker by remember { mutableStateOf(false) }
    val datePickerState = rememberDatePickerState(initialSelectedDateMillis = System.currentTimeMillis())
    val selectedDate = remember(datePickerState.selectedDateMillis) {
        val millis = datePickerState.selectedDateMillis ?: System.currentTimeMillis()
        val local = Instant.fromEpochMilliseconds(millis).toLocalDateTime(TimeZone.UTC)
        CalendarDate(local.year, local.monthNumber, local.dayOfMonth)
    }

    Dialog(onDismissRequest = onDismiss) {
        androidx.compose.material3.Surface(shape = MaterialTheme.shapes.large) {
            Column(modifier = Modifier.padding(24.dp)) {
                Text("Import \"${staged.programName}\"", style = MaterialTheme.typography.titleLarge)

                Text(
                    "Next workout in cycle",
                    style = MaterialTheme.typography.labelLarge,
                    modifier = Modifier.padding(top = 16.dp),
                )
                Row {
                    OutlinedButton(onClick = { cycleDayMenuExpanded = true }) {
                        Text(staged.cycleDayLabels.getOrElse(selectedCycleDayIndex) { "" })
                    }
                    DropdownMenu(expanded = cycleDayMenuExpanded, onDismissRequest = { cycleDayMenuExpanded = false }) {
                        staged.cycleDayLabels.forEachIndexed { index, label ->
                            DropdownMenuItem(
                                text = { Text(label) },
                                onClick = { selectedCycleDayIndex = index; cycleDayMenuExpanded = false },
                            )
                        }
                    }
                }

                Text(
                    "First day on calendar",
                    style = MaterialTheme.typography.labelLarge,
                    modifier = Modifier.padding(top = 16.dp),
                )
                OutlinedButton(onClick = { showDatePicker = true }) {
                    Text("${selectedDate.year}-${selectedDate.month}-${selectedDate.day}")
                }

                if (staged.autoCarryover.isNotEmpty() || staged.suggestions.isNotEmpty()) {
                    HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))
                    Text("Carry over previous weights", style = MaterialTheme.typography.labelLarge)
                    if (staged.autoCarryover.isNotEmpty()) {
                        Text(
                            "${staged.autoCarryover.size} exercise(s) matched by name — reference weights carry over automatically.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    LazyColumn(modifier = Modifier.padding(top = 8.dp)) {
                        items(staged.suggestions) { suggestion ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(suggestion.newExercise.exerciseName)
                                    Text(
                                        "Carry over weights from “${suggestion.oldExerciseName}”?",
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                }
                                Switch(
                                    checked = suggestion.id in confirmedSuggestionIds,
                                    onCheckedChange = { checked ->
                                        confirmedSuggestionIds = if (checked) {
                                            confirmedSuggestionIds + suggestion.id
                                        } else {
                                            confirmedSuggestionIds - suggestion.id
                                        }
                                    },
                                )
                            }
                        }
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
                    horizontalArrangement = Arrangement.End,
                ) {
                    TextButton(onClick = onDismiss) { Text("Cancel") }
                    Button(onClick = { onConfirm(selectedCycleDayIndex, selectedDate, confirmedSuggestionIds) }) {
                        Text("Import")
                    }
                }
            }
        }
    }

    if (showDatePicker) {
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = { TextButton(onClick = { showDatePicker = false }) { Text("OK") } },
            dismissButton = { TextButton(onClick = { showDatePicker = false }) { Text("Cancel") } },
        ) {
            DatePicker(state = datePickerState)
        }
    }
}

private fun displayNameOf(context: Context, uri: Uri): String? {
    context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) {
            val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0) return cursor.getString(idx)
        }
    }
    return null
}

private fun copyUriToCacheFile(context: Context, uri: Uri): File {
    val file = File(context.cacheDir, "import_staged.xlsx")
    val input = context.contentResolver.openInputStream(uri) ?: throw ProgramImportError.InvalidXlsxArchive
    input.use { stream -> file.outputStream().use { output -> stream.copyTo(output) } }
    return file
}

private object NotificationPermissionAsked {
    private const val PREFS_NAME = "notification_permission_asked"
    private const val KEY = "asked"
    fun load(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getBoolean(KEY, false)
    fun save(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit().putBoolean(KEY, value).apply()
    }
}

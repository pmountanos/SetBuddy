# Architecture Document

## Project Name
Set Buddy

## Bundle identifier (as-built)
`net.mountanos.Set-Buddy` (plus `…Set-BuddyTests` / `…Set-BuddyUITests` for test bundles).

## Architecture Objective
Provide a simple, maintainable technical structure for an iPhone-first fitness app without overengineering the first release.

## As-built summary
- **Stack:** SwiftUI, MVVM (`@Observable` view models), **SwiftData**, `UserNotifications`, **ZIPFoundation** (SPM) for `.xlsx` ZIP **read** (import) and **write** (minimal OOXML zip for export).
- **Entry:** `Set_BuddyApp` → `MainTabView` → five tabs; `AppRouter` (`selectedTab`, `selectedWorkoutId`, `openWorkoutLogging`).
- **Persistence:** SwiftData models in `Data/Persistence/`; business scheduling in domain types; **notification preferences** and **import first-calendar-day** preference in **UserDefaults** (not a SwiftData entity).
- **View model composition:** Larger screens split their state into focused, composed `@Observable` objects rather than one large view model — `ProgramOverviewViewModel` owns a `WorkoutTemplateEditorViewModel`; `SettingsViewModel` is a thin container owning `NotificationSettingsViewModel`, `ImportViewModel`, `ExportViewModel`.
- **Reschedule notifications:** `DailyNotificationScheduler.requestReschedule(modelContext:)` is the single fire-and-forget entry point every mutation site calls (program/schedule edits, workout completion, import, Settings changes) — no call site wraps `Task { await ... }` itself.
- **Tests:** `Set BuddyTests` (Swift Testing, `@testable import Set_Buddy`), `Set BuddyUITests` (XCTest). Shared scheme: `Set Buddy.xcodeproj/xcshareddata/xcschemes/Set Buddy.xcscheme`. Bundled fixtures: `Set Buddy.xlsx`, `Fixtures/Set Buddy-2.xlsx`.
- **UI automation:** Launch argument `-uiTesting` → `UITestLaunch.isUITesting` → skip notification permission request; **in-memory** SwiftData (see `Set_BuddyApp`).
- **App icon:** `Assets.xcassets/AppIcon.appiconset` — 1024× source `AppIcon-1024.png` (SF Symbol `figure.strengthtraining.traditional` on **royal blue** `#4169E1`, matching Workout tab glyph); regenerate via `scripts/generate_app_icon.swift`.
- **Versioning:** `MARKETING_VERSION` (human-facing release number, bumped manually — currently `1.0`) and `CURRENT_PROJECT_VERSION` (build number) are Xcode build settings, `VERSIONING_SYSTEM = "apple-generic"` on every target. **Both archive scripts auto-bump the build number** (`xcrun agvtool -noscm next-version -all`, writes directly into `project.pbxproj`, all targets uniformly) before archiving — commit the bump if you want it tracked. `GENERATE_INFOPLIST_FILE = YES` means these build settings *are* `CFBundleShortVersionString` / `CFBundleVersion`; no physical `Info.plist` to keep in sync. Shown in-app as **Settings → “Version 1.0 (5)”** footer (`SettingsScreen.appVersionString`, reads `Bundle.main.infoDictionary`).
- **Dev IPA (command line):** `scripts/archive_and_export_ipa.sh` — bumps build number, archives **Debug** for `generic/platform=iOS`, exports with `build/ExportOptions-Development.plist` (team `XXXXXXXXXX`, automatic signing) to **`build/ipa/Set Buddy <version> (<build>).ipa`** (fixed archive path `build/Set_Buddy.xcarchive`, re-used/overwritten each run — not timestamped).
- **Ad hoc / App Store IPA (command line):** `scripts/archive_and_export_production_ipa.sh [ad-hoc|app-store]` — bumps build number, archives **Release**, exports with `build/ExportOptions-AdHoc.plist` / `-AppStore.plist` to **`build/ipa-adhoc/Set Buddy <version> (<build>) ad-hoc.ipa`** or **`build/ipa-appstore/… app-store.ipa`**.

## Android (Kotlin Multiplatform) — as-built (Phase 1: 2026-09-12, Phase 2 import + Phase 3 parity: 2026-09-16)
Set Buddy gained an Android build without becoming a rewrite: a Gradle multi-module project sits alongside the Xcode project in this same repo (`settings.gradle.kts`, `shared/`, `androidApp/` at the repo root).

- **`shared` module (KMP — Android + iOS targets, `net.mountanos.setbuddy.shared`):**
  - `domain/` — 1:1 Kotlin port of `Domain/`'s pure-Foundation Swift (`CalendarDate`, `ScheduledDayKind`, `ProgramCalendarSchedule`, `TodayScheduleStatus`, `TodayScheduleResolver`, `VolumeCalculator`, `StringSimilarity`, `WorkoutTemplateDisplaySort`, `ExerciseCarryoverMatcher`), using `kotlinx-datetime` and `kotlin.uuid.Uuid` in place of `Foundation`'s `Date`/`Calendar`/`UUID`.
  - `shared/db` — **SQLDelight** schema (`shared/src/commonMain/sqldelight/.../SetBuddy.sq`) mirroring the 6 `Persisted*` SwiftData models (`Program`, `Workout`, `ScheduleEntry`, `Exercise`, `WorkoutSession`, `LoggedSet`) as real SQL tables with `ON DELETE CASCADE` foreign keys. Unlike the `.xlsx` subsystem, persistence itself is genuinely shared cross-platform from one schema — only `DatabaseDriverFactory` is `expect`/`actual` (`AndroidSqliteDriver` / `NativeSqliteDriver`).
  - `shared/data` — `ProgramRepository`, `WorkoutSessionRepository`, `HistoryRepository`, `ProgramOutlineRepository`: Kotlin ports of the same-named Swift repositories' method surface (schedule CRUD + cascade, session lifecycle, history queries, program outline), built on the generated SQLDelight query classes.
  - iOS target compiles (`iosMain` has a working `NativeSqliteDriver` actual) but nothing in the Xcode app links against it yet — that hookup is explicit Phase 2 scope, not attempted here.
- **`androidApp` module (Jetpack Compose, `net.mountanos.setbuddy.android`, applicationId `net.mountanos.setbuddy`):** same 5-tab shape as iOS — Today / Program / History / Settings bottom nav plus a Workout Logging screen pushed from Today. Each screen is a Compose function calling straight into the shared repositories (no separate Android ViewModel layer — same "thin UI, business logic lives below" shape as the iOS view models, just without the intermediate object). First run calls the same `createFirstProgram` starter path iOS uses for real installs (not `seedIfNeeded`'s UI-test-only demo data). At feature parity with iOS as of 2026-09-16: Program tab has a workout editor dialog (rename/reorder/add/delete exercises, set count, per-side) and a real schedule-day dropdown; Today has the "Change today's plan" menu; exercise/session notes are editable from Program, Workout Logging, and History via a shared `ui/NoteEditorDialog.kt`; Workout Logging shows a live session-volume row and a Finish confirmation step; History shows per-row/per-detail/per-exercise volume.
- **`androidApp/.../importxlsx/`** — Kotlin port of `Data/Import/*.swift`: `ProgramXlsxParser` (SAX via `javax.xml.parsers` + `java.util.zip.ZipFile` in place of `XMLParser`/ZIPFoundation), `ProgramXlsxImporter`, `ProgramImportError`, `ImportedProgramDisplayNaming` — same column-mapping precedence, rest-day detection, per-side markers, and exercise-carryover matching (reusing `ExerciseCarryoverMatcher` from `shared`) as iOS. Wired into Settings via a staging dialog (cycle-day picker, calendar start-date picker, carryover confirmation).
- **`androidApp/.../export/`** — Kotlin port of `Data/Export/*.swift`: `SpreadsheetFormatting`, `MinimalXlsxArchive` (writes via `java.util.zip.ZipOutputStream`, DEFLATE — iOS uses STORED/no-compression; both are valid zips, so this is a safe simplification, not a format difference an OOXML reader would notice), `ProgramSpreadsheetExport`, `HistorySpreadsheetExport`, `ExportFileWriter` (xlsx-then-CSV fallback). Shared via a `FileProvider` (`res/xml/file_paths.xml`, manifest `<provider>`) + `Intent.ACTION_SEND` chooser — the Android equivalent of iOS's `UIActivityViewController` share sheet.
- **Notifications:** `androidApp/.../notifications/DailyNotificationScheduler.kt` ports `DailyNotificationScheduler.swift`'s algorithm exactly (same per-day title/body copy, same 14-day horizon, same `net.mountanos.setbuddy.schedule.<y>-<m>-<d>` id scheme) onto `AlarmManager.setExactAndAllowWhileIdle` + a `DailyReminderReceiver`/`BootRescheduleReceiver` pair; needs the user to grant the OS's "Alarms & reminders" special access (Android 13+) for exact alarms to actually schedule — this is a normal Android system permission prompt/setting, not an app bug, and the scheduler no-ops safely without it.
- **Not yet ported:** linking the `shared` KMP framework into the Xcode build (the `iosMain` source set compiles but nothing in the iOS app calls into it yet).
- **Build tooling:** `scripts/build_android.sh` bumps `androidApp/build.gradle.kts`'s `versionCode` then runs `./gradlew :androidApp:assembleDebug`, mirroring the iOS archive scripts' auto-bump-on-build convention. Needs `JAVA_HOME` set to a JDK — Android Studio's bundled JBR works (`/Applications/Android Studio.app/Contents/jbr/Contents/Home`), no separate install required. Gradle wrapper targets AGP 8.7.3 / Kotlin 2.0.21 / SQLDelight 2.0.2 / compileSdk 36 / minSdk 26.

## Technical Stack
- SwiftUI
- MVVM
- SwiftData
- UserNotifications
- ZIPFoundation (package)
- **Android:** Kotlin Multiplatform, SQLDelight, Jetpack Compose, AlarmManager

## Architectural Style
Layered structure:

- Presentation layer
- Domain layer
- Data layer
- Platform layer

## Repository layout (actual)
Source root for the app target (Xcode synchronized group):  
`Set Buddy/Set Buddy/`

```
Set Buddy/
  Set_BuddyApp.swift
  App/
    AppRouter.swift
  Presentation/
    MainTabView.swift
    ExerciseNoteSheet.swift   // `ExerciseNoteEditorSheet`
    Today/
    WorkoutLogging/
    ProgramOverview/
      ProgramOverviewScreen.swift
      ProgramOverviewViewModel.swift
      WorkoutTemplateEditorSheet.swift
      WorkoutTemplateEditorViewModel.swift  // owned by ProgramOverviewViewModel
    History/
      HistoryScreen.swift
      HistorySessionDetailView.swift
    Settings/
      SettingsScreen.swift
      SettingsViewModel.swift          // thin container
      NotificationSettingsViewModel.swift
      ImportViewModel.swift
      ExportViewModel.swift
      ShareExportSheet.swift
  Domain/
    Models/
      CalendarDate.swift
      ProgramCalendarSchedule.swift
      ScheduledDayKind.swift
      TodayScheduleStatus.swift
    Services/
      TodayScheduleResolver.swift
      VolumeCalculator.swift
      WorkoutTemplateDisplaySort.swift
      StringSimilarity.swift            // Levenshtein-based ratio, generic
      ExerciseCarryoverMatcher.swift     // exercise name matching policy for import carryover
  Data/
    Persistence/
      PersistedProgramModels.swift      // PersistedProgram, PersistedWorkout, PersistedScheduleEntry
      PersistedWorkoutLoggingModels.swift // PersistedExercise, PersistedWorkoutSession, PersistedLoggedSet
      ModelContext+Find.swift           // ModelContext.first(_:matching:) predicate-fetch helper
    Repositories/
      ProgramRepository.swift
      WorkoutSessionRepository.swift
      ProgramOutlineRepository.swift
      HistoryRepository.swift
    Import/
      ProgramXlsxParser.swift
      ProgramXlsxImporter.swift
      XlsxArchiveReader.swift
      ProgramImportError.swift
    Export/
      ExportError.swift
      SpreadsheetFormatting.swift   // worksheet XML, cell values, csvEscape/csvData
      MinimalXlsxArchive.swift      // ZIPFoundation write; workbook + sheet rels
      ProgramSpreadsheetExport.swift
      HistorySpreadsheetExport.swift
  Platform/
    Notifications/
      NotificationPermission.swift
      NotificationSettings.swift       // UserDefaults-backed struct
      DailyNotificationScheduler.swift
    Utilities/
      DateProvider.swift
      UITestLaunch.swift
```

There is no separate `UseCases/` or `Resources/` subtree in sync with the above; assets live under the Xcode project as usual.

## Layer Responsibilities

### Presentation Layer
- Screens, view models, tab navigation, sheets, file importer (Settings), export share sheet.
- Does **not** own low-level import ZIP/XML (delegates to `Data/Import`) or OOXML assembly (delegates to `Data/Export`).

### Domain Layer
- **Value types:** `CalendarDate`, `ProgramCalendarSchedule`, `ScheduledDayKind`, `TodayScheduleStatus`.
- **Pure logic:** `TodayScheduleResolver`, `VolumeCalculator` (`nonisolated` where used from background-safe code paths).

### Data Layer
- SwiftData `@Model` types and repositories.
- Import pipeline: parse `.xlsx` → replace program + schedule (see `ProgramXlsxImporter` for session retention rules).
- Export helpers: **`Data/Export`** builds program/history spreadsheets (see **Export** under repositories / **Export strategy**).

### Platform Layer
- Notifications, date provider abstraction, UI-test launch flag.

## Presentation (as-built)

| Screen | Files |
|--------|--------|
| Today | `TodayScreen.swift`, `TodayViewModel.swift` |
| Workout | `WorkoutLoggingScreen.swift`, `WorkoutLoggingViewModel.swift` |
| Program | `ProgramOverviewScreen.swift`, `ProgramOverviewViewModel.swift` (+ `WorkoutTemplateEditorSheet.swift` / `WorkoutTemplateEditorViewModel.swift` for the per-workout editor sheet) |
| History | `HistoryScreen.swift`, `HistoryViewModel.swift`, `HistorySessionDetailView.swift` |
| Settings | `SettingsScreen.swift`, `SettingsViewModel.swift` (container) + `NotificationSettingsViewModel.swift` / `ImportViewModel.swift` / `ExportViewModel.swift`, `ShareExportSheet.swift` (`UIActivityViewController` wrapper) |

**Settings view model split:** `SettingsViewModel` owns three independent `@Observable` children instead of one large object — `notifications` (daily-reminder toggle/time/authorization), `importer` (staging + carryover confirmation + confirm), `exporter` (program/history spreadsheet export). `SettingsScreen` binds to each directly (`@Bindable var notifications = viewModel.notifications`, etc.) rather than through the parent.

**Program template editor split:** `ProgramOverviewViewModel.workoutEditor` (`WorkoutTemplateEditorViewModel`) owns the workout-template-editor sheet's own state (name, exercise rows, add/rename/reorder/delete) and is passed directly to `WorkoutTemplateEditorSheet`; the parent only delegates `presentWorkoutEditor(workoutId:)` / `onWorkoutEditorDismissed()`.

**Today schedule override:** `TodayScreen` shows a **“Change today’s plan”** menu (Rest + every workout) whenever a program exists, backed by `TodayViewModel.forceTodaysSchedule(to:)` — see **Domain (as-built) → Schedule and today** and **Implementation notes → Schedule realignment**.

**Version footer:** `SettingsScreen` shows a centered, secondary-style **“Version 1.0 (5)”** line below Export — see **As-built summary → Versioning**.

**Shared UI:** `ExerciseNoteEditorSheet` (in `ExerciseNoteSheet.swift`) — `TextEditor`, **Cancel** / **Save** (`exerciseNoteSaveButton`, `exerciseNoteEditor` for testing).

**Settings export:** **`ExportViewModel.exportProgram`** / **`exportHistory`** load SwiftData (`PersistedProgram`, **`HistoryRepository.allCompletedSessionDetails()`**), build **`.xlsx`** via **`ProgramSpreadsheetExport`** / **`HistorySpreadsheetExport`** through the shared **`writeExportFile(prefix:buildXlsx:buildCsv:)`** helper, fall back to **`.csv`** on failure; write under **`FileManager.default.temporaryDirectory`** with stamped names **`Set_Buddy_Program_yyyy-MM-dd_HHmmss`** / **`Set_Buddy_History_yyyy-MM-dd_HHmmss`**; present **`exportPresentation`** → **`.sheet`** → **`ShareExportSheet`**; **`finishExportSharing()`** deletes the temp file. UI copy and **`exportError`** surface failures; **`settingsExportProgramButton`** / **`settingsExportHistoryButton`** for UI tests.

**Workout logging UI:** Private set row views in `WorkoutLoggingScreen` — `TextField` + **decimal pad** / **number pad**, shared `@FocusState` owned on **`WorkoutLoggingScreen`** (passed into content/rows). **`WorkoutLoggingViewModel`** loads **reference** weight/reps from the **last completed** session for the same workout template (display only). **Reference** values use **orange-filled** fields with **white** text; **committed** values (`PersistedLoggedSet.userEditedValues`) use a **dark/light filled** field with contrasting text (neutral rounded-border fields when there is no prior reference). A **Done** button in **`safeAreaInset(edge: .bottom)`** (above the session volume bar) commits the row and calls **`resignFirstResponderGlobally()`**—system **keyboard accessory** `ToolbarItem(placement: .keyboard)` is **not** relied on for number pads inside `List`. Toolbar **Finish** dismisses the keyboard, commits the focused field, then opens a **confirmation** step; only sets the user entered are kept in SwiftData (see Implementation notes).

## Domain (as-built)

### Schedule and today
- **`ProgramCalendarSchedule`:** in-memory map from `CalendarDate` → `ScheduledDayKind` (workout id or rest).
- **`TodayScheduleResolver.status`:** `noProgram` / `dayNotScheduled` / `restDay` / `workoutDay(workoutId:title:)`.
- **`TodayViewModel`** (after resolver): may map `workoutDay` → **`workoutAlreadyFinished(title:)`** when `WorkoutSessionRepository.hasCompletedSession` is true for **today** and template id; or → **`workoutInProgress(workoutId:title:)`** when `activeSession` exists for today and that template; otherwise leaves **`workoutDay`**. **`TodayScreen`** calls **`refresh()`** when **`AppRouter.selectedTab`** becomes **`.today`** so the tab stays in sync after logging on **Workout**.
- **`TodayViewModel.forceTodaysSchedule(to:)`:** realigns the rotation after a missed day — forces today onto a chosen workout (or rest) via `ProgramRepository.setScheduleDayShiftingFollowing(from: today, value:, calendar:)`, the same cascade the Program tab’s per-day schedule menu uses, then refreshes. `availableWorkoutsForOverride` (from `ProgramOutlineRepository`) feeds the “Change today’s plan” menu. See **Implementation notes → Schedule realignment**.
- **`WorkoutTemplateDisplaySort`:** canonical ordering for Program outline workout sections (Push 1, Pull 1, Legs 1, …).
- **`CalendarDate`:** canonical schedule key; explicit `Calendar` for `Date` conversion (Swift 6–friendly).

### Persistence models (SwiftData)
| Concept | Type |
|--------|------|
| Program | `PersistedProgram` |
| Schedule row | `PersistedScheduleEntry` (Y/M/D, rest flag, optional `workoutID`) |
| Workout template | `PersistedWorkout` |
| Template exercise | `PersistedExercise` (`note`, `setCount`, `sortOrder`) |
| Session | `PersistedWorkoutSession` (template id, calendar day, `loggedSets`, snapshots) |
| Logged set | `PersistedLoggedSet` (`weight`, `reps`, `userEditedValues`, `seededFromCarryover` legacy/unused, `repsArePerSide`, etc.) — **only rows the user entered** remain after finish |

There is no separate `PlannedSet` entity: template **set count** lives on `PersistedExercise`.

`PersistedLoggedSet.seededFromCarryover` remains unused/always-`false`: the **import** carryover feature (see below) works by preserving `PersistedExercise.id` across a re-import, not by seeding this field, so it's still legacy scaffolding rather than dead code worth removing (removing an unused SwiftData model field is a schema change out of proportion to the cleanup).

### “Services” naming
Early doc listed `CarryoverService`, `ImportService`, etc. **As-built:** **prior-session values** for logging are resolved in **`WorkoutLoggingViewModel`** (from `WorkoutSessionRepository.mostRecentLoggedValuesByExercise`) for **UI reference only**; new sessions start with **zero** stored weight/reps per set until the user commits entry. Import in `ProgramXlsxParser` / `ProgramXlsxImporter`; import-time exercise-identity matching in `ExerciseCarryoverMatcher` (+ `StringSimilarity`); volume in `VolumeCalculator`; notifications in `DailyNotificationScheduler`.

## Data layer (as-built)

### Repositories
- **`ProgramRepository`:** active program, `calendarSchedule(for:)`, `workoutTitles(for:)`, forward schedule fill, `createFirstProgram` / `startOverFreshProgram`, template + schedule CRUD (`renameProgram`, `addWorkout`, `setScheduleDay`, `setScheduleDayShiftingFollowing`, …), `seedIfNeeded` (UI tests only), legacy title migration; template exercise backfill for empty templates. Exercise setters (`setExerciseName`, `setExerciseSetCount`, `setExerciseRepsPerSide`, `setExerciseNote`, `deleteExercise`) go through a private `requireExercise(id:)` helper and **throw** `ProgramEditingError.exerciseNotFound` / `.workoutNotFound` instead of silently no-oping on a missing id — the caller decides whether to surface that (most `try?` for autosave-style edits; see **Implementation notes**).
- **`WorkoutSessionRepository`:** get/create session for calendar day; **`populateMissingLoggedSets`** (single method, covers both "new session" and "template gained sets") inserts **`PersistedLoggedSet`** rows with **weight 0 / reps 0** (no copy from prior session into the store); **`hasCompletedSession(templateId:day:)`**; **`mostRecentLoggedValuesByExercise()`** returns the most recent logged value per `(exerciseId, setIndex)` **across all completed sessions, any workout** — this is what the workout logger's reference-weight hints use, and it's scoped by exercise identity (not workout template id) specifically so **`ExerciseCarryoverMatcher`**-preserved ids keep surfacing history after a program re-import. Also owns the SwiftData writes `WorkoutLoggingViewModel` used to do directly: `updateLoggedSet`, `completeSession`, `setSessionNote`.
- **`ProgramOutlineRepository`:** read-only program outline (workouts sorted via **`WorkoutTemplateDisplaySort`**) + **upcoming schedule rows** (next N days; N from **`ProgramSchedulePreviewDaysSetting`** / Settings).
- **`HistoryRepository`:** completed session rows; **`sessionDetail(sessionId:)`** for drill-down — exercise names resolve from the session's original workout template first, then fall back to the **current** active program's exercises by id (works when the exercise was carried over at import; otherwise falls back to a generic "Exercise" label as before); **`allCompletedSessionDetails()`** returns every finished session as **`HistorySessionDetail`** (newest first) for **history export**.
- **`ModelContext.first(_:matching:)`** (`Data/Persistence/ModelContext+Find.swift`): shared `#Predicate`-based single-result fetch helper used across repositories instead of `fetch(FetchDescriptor<T>())` + `.first(where:)` full-table scans.

### Import
- **`XlsxArchiveReader`:** ZIPFoundation `Archive(data:accessMode: .read)`, entry lookup.
- **`ProgramXlsxParser`:** workbook → cycle of days (sheet order).
- **`ProgramXlsxImporter`:** writes SwiftData program + schedule horizon; **`cycleStartIndex`** maps the user’s “next” worksheet day to the import start date; preserves completed sessions (see code for title snapshot backfill rules). Two overloads: `xlsx: Data` (parses then delegates) and `cycle: [XlsxCycleDay]` (already-parsed — used by the Settings staging flow so the workbook isn't parsed twice for one import). Both take an optional **`exerciseCarryover: [ImportExerciseRef: UUID]`** — when a new exercise's `(workoutSheetName, exerciseName)` is a key in the map, the new `PersistedExercise` reuses that id instead of a fresh one.
- **`ExerciseCarryoverMatcher`** (`Domain/Services/`): the matching policy behind `exerciseCarryover`. Matches the program about to be replaced against the freshly parsed workbook, by exercise name only (not workout name): exact (case/whitespace-insensitive) matches auto-apply; close matches (`StringSimilarity.ratio >= fuzzyThreshold` = **0.75**, Levenshtein-based) are offered as `Suggestion`s for the user to confirm; greedy highest-score-first assignment prevents one old exercise being suggested for two different new ones. See **Implementation notes → Exercise carryover on import**.

### Export
- **`ProgramSpreadsheetExport`:** **`.xlsx`** — one worksheet per workout (**`WorkoutTemplateDisplaySort`**), header row **`Exercise_Name`**, **`Notes`**, **`Per side`** (same as import). **`.csv`** — program name, per-workout **`exercise`** rows with **`set_count`**, then **`schedule`** rows (ISO date, rest/workout, workout name).
- **`HistorySpreadsheetExport`:** single sheet; columns include **`completed_at`**, **`workout`**, **`schedule_day`**, **`total_volume`**, **`exercise`**, **`set_number`**, **`weight_kg`**, **`reps`**, **`per_side`**, **`set_volume`**. After each session’s set rows, a **`workout_total`** row repeats session metadata and puts the **sum of `set_volume`** for that session in **`set_volume`** (detail columns blank).
- **`SpreadsheetFormatting.csvEscape(_:)` / `.csvData(lines:)`:** shared CSV quoting and UTF-8-BOM assembly, used by both export types instead of each duplicating it.
- **`MinimalXlsxArchive`:** builds a minimal Office Open XML zip (content types, workbook, worksheet XML, rels) using **ZIPFoundation** `Archive` create/update.
- **`ExportError`:** e.g. **`noActiveProgram`**, **`couldNotCreateArchive`** — surfaced via **`ExportViewModel.exportError`**. **`ExportViewModel.writeExportFile(prefix:buildXlsx:buildCsv:)`** is the one place that implements "try `.xlsx`, fall back to `.csv`, write to a stamped temp file" — both `exportProgram` and `exportHistory` call it instead of duplicating the flow.

## Platform (as-built)

- **`NotificationPermission`:** `requestIfNeeded`, `requestAuthorization()`.
- **`NotificationSettings`:** load/save from `UserDefaults` (optional suite for tests); enabled flag + hour/minute.
- **`DailyNotificationScheduler`:** clears prior prefixed requests; respects `NotificationSettings`; uses `TodayScheduleResolver` per day for message body. **`notificationContent(for:)`** must handle every **`TodayScheduleStatus`** case; scheduling only ever passes resolver output (`workoutDay`, `restDay`, etc.), while **`workoutInProgress`** is grouped with **`workoutDay`** for shared copy when needed. **`DailyNotificationScheduler.requestReschedule(modelContext:)`** is a `static` fire-and-forget entry point (wraps `Task { await shared.reschedule(modelContext:) }` once, internally) — every call site (`MainTabView` launch, `TodayViewModel.refresh`, workout completion, program/schedule edits, import confirm, Settings notification changes) calls this instead of each wrapping its own `Task`.
- **`DateProviding` / `SystemDateProvider`:** testable “now” for Today.

## Data flow (typical)
User action → SwiftUI view → **ViewModel** → **Repository** / parser → **SwiftData** `ModelContext` → save → view model refresh → UI.

## State management
- **Tab + workout selection:** `AppRouter` in environment.
- **Per-screen:** `@Observable` view models; SwiftData `@Environment(\.modelContext)`.

## Persistence strategy
- **Production:** on-disk SwiftData (single container in `Set_BuddyApp`).
- **UI tests:** `-uiTesting` forces **in-memory** container for isolation.

## Notification strategy
- Local notifications only; content driven by same schedule/titles as UI.
- Reschedule triggered from app launch path, Today refresh, schedule force/cascade, workout completion, import, and Settings changes — all via `DailyNotificationScheduler.requestReschedule(modelContext:)`.

## Import strategy
- Validation and parsing in **Data/Import**; Settings **file importer** → **`ImportViewModel.stageImportFromPickedFile(url:modelContext:)`** (also runs `ExerciseCarryoverMatcher`, see **Implementation notes**) → confirmation **sheet** (cycle day picker + date + carryover suggestions) → **`confirmStagedImport`** runs importer.
- UserDefaults: **import first calendar day** (`ImportViewModel.importScheduleStartDate`).
- Default **4** sets per exercise when not specified in sheet (`ProgramXlsxParser`); seed templates use 4 (`ProgramRepository`).

## Export strategy
- Generation in **`Data/Export`**; no reverse import for history CSV (backup/analysis only). Program **`.xlsx`** is intended to round-trip through **`ProgramXlsxImporter`** (workout sheets only; CSV schedule is export-only documentation of the stored horizon).

## Testing strategy (as-built)
- **Unit:** Swift `Testing` framework in `Set BuddyTests` — calendar, schedule resolver, volume, import errors, notification prefs round-trip, **`WorkoutTemplateDisplaySort`**, SwiftData-backed repository methods, bundled `.xlsx` parse; **`WorkoutSessionRepository`** set-count grow/shrink sync + per-side propagation + `updateLoggedSet`/`completeSession`; **`WorkoutTemplateEditorViewModel`** add/rename/reorder; **`TodayViewModel.forceTodaysSchedule`** cascade + refresh (via a `StubDateProvider`); xlsx export round-trips through `XlsxArchiveReader`; **`StringSimilarity`** and **`ExerciseCarryoverMatcher`** (exact/fuzzy/no-match/greedy-assignment) plus an end-to-end re-import carryover test. The suite is `@Suite(.serialized)` — Swift Testing's default concurrent execution isn't safe with this many tests each spinning up their own in-memory `ModelContainer` (reproduced a SIGTRAP crash under parallel load).
- **UI:** `Set BuddyUITests` — tab navigation, Program/Settings smoke, Today → Finish → History + detail, **Start hidden after same-day completion** (`todayStartWorkoutButton`), **Continue shown when session in progress** (`todayContinueWorkoutButton`); launch uses `-uiTesting`. Two tests (`testProgramTabShowsSeededProgramAndWorkouts`, `testHistoryOpensSessionDetailWithSetRows`) are known-flaky/pre-existing-broken on this machine's iOS 26.5 simulator (an `app.staticTexts[...]` assertion likely doesn't match a SwiftUI `TextField`'s accessibility role) — confirmed via an A/B run against pre-refactor code, not a regression, not yet fixed.
- **Scheme:** Both test bundles attached in shared `.xcscheme` (UITests enabled).

## Implementation notes (as-built)

Details that are easy to miss when reading only high-level flows.

### UserDefaults keys (standard suite)
| Area | Key | Notes |
|------|-----|--------|
| Import start date | `importScheduleStartDateSince1970` | `TimeInterval` for first calendar day used in import staging (`ImportViewModel`). |
| Daily reminders | `notificationSettings.dailyRemindersEnabled` | With `notificationSettings.reminderHour` / `reminderMinute` (`NotificationSettings`). |
| Program tab schedule length | `programOverview.schedulePreviewDays` | Integer day count; must be one of **7, 14, 21** or load falls back to **14** (`ProgramSchedulePreviewDaysSetting`). |

### Workout logging: reference vs persisted
- **`WorkoutSessionRepository`** creates **`PersistedLoggedSet`** rows with **stored** `weight` / `reps` at **0** until the user commits a change; it does **not** copy the previous session into SwiftData.
- **`WorkoutLoggingViewModel.rebuildSections`** fills **`SetRow.referenceWeight` / `referenceReps`** from **`WorkoutSessionRepository.mostRecentLoggedValuesByExercise()`** (fetched once per rebuild, not per set) for display — scoped by **exercise id**, **any** workout, not the current workout template. **`WorkoutSetRowView.shouldMarkUserEntry`** sets **`markUserEntry`** to **true** when the user has **focused** weight or reps (focus snapshots present) and commits—**including when values still match reference**—so confirming last session’s numbers does not require a dummy edit. If the user never focused either field, **`markUserEntry`** still becomes true when parsed values differ from reference (fallback).
- **`updateLoggedSet(..., markUserEntry:)`** sets **`userEditedValues`** when persisting. **`completeWorkout`** removes all logged sets with **`!userEditedValues`** before completing the session.

### Exercise carryover on import
- **Problem:** re-importing a program regenerates every `PersistedExercise.id`. Since the reference-weight lookup above is keyed by exercise id, a naive re-import silently loses the "what did I lift last time" hint for every exercise, even ones that didn't really change.
- **Fix:** `SettingsScreen`'s import staging flow (`ImportViewModel.stageImportFromPickedFile`) runs `ExerciseCarryoverMatcher.match(existing:newCycle:)` against the program about to be replaced as soon as a file is picked. Exact name matches go straight into `stagedAutoCarryover` (applied silently). Close (`>= 0.75` similarity) matches become `stagedCarryoverSuggestions`, shown in a **"Carry over previous weights"** section on the staging sheet as pre-checked toggles (`stagedConfirmedSuggestionIds`) — the user can uncheck any that are wrong.
- On confirm, `ImportViewModel.confirmStagedImport` merges the auto matches with the confirmed suggestions into one `[ImportExerciseRef: UUID]` map and passes it to `ProgramXlsxImporter.importReplacingStore(..., exerciseCarryover:)`, which reuses those ids for the matching new `PersistedExercise` rows instead of generating fresh ones. The import confirmation message reports how many exercises carried over.
- Side effect: `HistoryRepository.sessionDetail`'s exercise-name fallback (see **Data layer → Repositories**) means History for old sessions also recovers correct exercise names when the exercise carried over, even though the workout template it was originally logged under is gone.

### Schedule realignment (force today's plan)
- The stored calendar schedule (`PersistedScheduleEntry`, one row per day) doesn't know about a repeating "cycle position" — it's a flat date → workout/rest mapping computed once at import/creation time. Missing days (e.g. travel) doesn't move anything; the *next* scheduled day still shows whatever was originally planned for that date, out of rotation order.
- **`ProgramRepository.setScheduleDayShiftingFollowing(from:value:calendar:skipIfUnchanged:)`** (pre-existing, used by the Program tab's per-day schedule menu) fixes this for one day at a time: assign `value` to `from`, then shift everything from `from` onward through the horizon forward by exactly one day. Because each day just inherits the *previous* day's old assignment, this single one-day shift is sufficient to keep the rest of the rotation's relative order correct regardless of how many days were actually missed — the user only needs to act on **today**, not backfill every missed day.
- **`TodayViewModel.forceTodaysSchedule(to:)`** surfaces this on the Today screen (previously only reachable from the Program tab) via the **"Change today's plan"** menu, scoped to "today" through the injected `DateProviding`.

### Cross-tab refresh
- Changing **Program → upcoming list length** in Settings persists via **`ProgramSchedulePreviewDaysSetting.save`** and posts **`Notification.Name.programSchedulePreviewDaysDidChange`**. **`ProgramOverviewScreen`** observes it and calls **`refresh()`** so the Program tab updates without a manual pull.

### Local notification identifiers
- Pending requests use prefix **`net.mountanos.setbuddy.schedule.`** (`DailyNotificationScheduler`). Reschedule removes all identifiers with that prefix before re-adding; horizon defaults to **14** days ahead (independent of the Program tab’s 7/14/21 **display** window).

### Stored schedule horizon vs Program list
- **`ProgramRepository.forwardScheduleHorizonDays`** is **196** (~28 weeks): `ensureForwardScheduleFilled`, **`createFirstProgram`**, **`ProgramXlsxImporter`** default import horizon, and UI-test seed all align on that window of **`PersistedScheduleEntry`** rows from **today**.
- The **Program** tab only **shows** **7, 14, or 21** rows from today (`ProgramOutlineRepository.upcomingScheduleRows(limit:)`); changing the setting does not shrink the underlying store.

### Spreadsheet column mapping (`ProgramXlsxParser`)
- One worksheet = one **cycle day**; tab order = cycle order.
- **Rest:** sheet name contains `"rest"` (case-insensitive) **or** no exercise rows.
- **Exercise names:** column **A** by default; row **1** can name columns—**Notes** and **Per side** / **Per set** headers are detected and mapped in flexible column order.
- **Legacy** (no row-1 headers): column **B** = note, **C** = per-side flag (`x`, `TRUE`, `1`, `yes`, etc.).
- **Default sets per imported exercise:** **4** (`ProgramXlsxParser`); same default for seed/template helpers in **`ProgramRepository`** unless templates already have exercises.

### Program title from filename (`ImportedProgramDisplayNaming`)
- When staging import, the suggested program name is derived from the file’s base name, then normalized: legacy names **`Workout Buddy`**, **`Workout Buddy-2`**, **`Workout Buddy 2`**, and bundled-style **`Set Buddy-2`**, **`Set Buddy 2`** map to display title **`Set Buddy`**.
- **`ProgramRepository.migrateLegacyImportedProgramTitles`** applies the same rules to **existing** `PersistedProgram.name` when the app loads (e.g. **`MainTabView` `.task`**) so old installs don’t keep stale titles.

### Replace program / import teardown
- **`ProgramXlsxImporter.removeAllProgramsPreservingCompletedHistory`**: backfill **`workoutTitleSnapshot`** on completed sessions, delete **incomplete** sessions, delete all programs. Used by **import** and by **`ProgramRepository.startOverFreshProgram`**.

### UI test bootstrap
- **`ProgramRepository.seedIfNeeded`** runs only when **`UITestLaunch.isUITesting`** (`-uiTesting`); production relies on **Create program** or import. **`MainTabView`** and **`TodayViewModel`** both gate seeding on that flag.

### Finish workout (logging)
- **`WorkoutLoggingScreen`** uses **`confirmationDialog`** so **Finish** is a two-step flow (avoid accidental completion). UITests tap **“Finish workout”** in that dialog. Copy explains that **only entered sets** are saved.
- **`WorkoutLoggingViewModel.completeWorkout`** deletes every **`PersistedLoggedSet`** with **`userEditedValues == false`** before marking the session complete, so **reference-only** values are never persisted. **Session volume** on the log screen sums only **`userEditedValues`** sets.

## Architectural constraints
- Local-first, single-user v1.
- Business logic not embedded in SwiftUI views beyond trivial glue.
- Repositories encapsulate fetch/save patterns; domain types avoid SwiftUI imports.

## Summary
Set Buddy is a **SwiftUI + MVVM + SwiftData** app with a thin **domain** layer for dates and schedule resolution, **repositories** for persistence and import, and a **platform** layer for notifications and test hooks. The architecture matches the first-release feature set; future features (sync, multi-program) should continue to sit behind repositories and explicit domain types.

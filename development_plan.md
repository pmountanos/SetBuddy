# Development Plan

## Project Name
Set Buddy

## As-built status (September 2026)

Phases **1–10** are implemented in code. **Phase 11** has substantial **automated** coverage (unit + UI tests + shared Xcode scheme); **manual** checks from the plan (midnight boundaries, denied notifications, small-device passes, etc.) remain good pre-release practice.

**September 2026 pass — refactor + two feature additions:**
- **Refactor** (no behavior change except where noted): repository layer deduplicated (`ModelContext.first(_:matching:)` helper, `ProgramRepository.requireExercise`, `HistoryRepository`/`ProgramXlsxImporter` reuse `workoutTitles(for:)` instead of rebuilding it, `WorkoutSessionRepository`'s duplicate populate/sync methods merged, several full-table fetches switched to `#Predicate`); `ProgramOverviewViewModel` split out `WorkoutTemplateEditorViewModel`; `SettingsViewModel` split into a thin container over `NotificationSettingsViewModel` / `ImportViewModel` / `ExportViewModel`; `SpreadsheetFormatting.csvEscape`/`.csvData` and `ExportViewModel.writeExportFile` removed duplicated export code; fixed a double-parse of the workbook on import; `ProgramRepository`'s exercise CRUD now throws typed `ProgramEditingError` instead of silently no-oping; `DailyNotificationScheduler.requestReschedule` replaced 8 scattered `Task { await ... }` call sites; removed two pieces of dead code (`VolumeCalculator`'s unused overload, `ProgramOverviewViewModel.schedulePickerValue(for:)`). ~14 new unit tests added for previously-uncovered repository/view-model logic.
- **Feature — schedule realignment:** **Today** screen gained a **"Change today's plan"** menu (`TodayViewModel.forceTodaysSchedule`) so missing a day (travel, etc.) can be fixed from Today instead of requiring the Program tab; reuses the existing `setScheduleDayShiftingFollowing` cascade. See requirements §15.
- **Feature — exercise carryover on import:** re-importing a program now matches the new workbook's exercises against the one being replaced **by name** (exact → silent carryover; ≥75% similar → user confirms via a new staging-sheet section) and reuses the matched exercise's id, so the workout logger's reference-weight hints survive the re-import. The reference lookup itself (`WorkoutSessionRepository.mostRecentLoggedValuesByExercise`, replacing `mostRecentCompletedSession`) is now scoped by exercise identity across all completed sessions rather than by workout template, which is what makes the carried-over id actually resurface history. `HistoryRepository` also gained a fallback so History correctly names exercises from sessions whose original workout template no longer exists. See requirements §16.
- **Build tooling — version numbering:** `CURRENT_PROJECT_VERSION` (build number) is now auto-bumped by both archive scripts (`xcrun agvtool -noscm next-version -all`, all targets, `VERSIONING_SYSTEM = "apple-generic"`) instead of sitting static; `MARKETING_VERSION` stays manual. Settings gained a **“Version 1.0 (5)”** footer, and exported `.ipa` files are now named with version + build (`Set Buddy 1.0 (5).ipa`, `… (5) ad-hoc.ipa`, etc.) instead of a bare `Set Buddy.ipa` — driven by wanting to track down issues in builds shared with friends, not just personal use. Prompted a standing instruction: update these four `.md` docs every time a build is requested (see project memory).

**Late March 2026 UX/data pass (documented across `.md` files):** kg-only UI; decimal/number-pad set entry (no +/- steppers); editable exercise notes; import confirmation sheet (**next cycle day** + first calendar day); Today omits **Start** when today’s workout is already completed; Program tab workout order (Push 1 / Pull 1 / …); default **4** sets from import/seed; app icon matches Workout tab SF Symbol.

**April 2026 pass:** **Today** shows **Continue** when today’s scheduled workout has an **in-progress** session; **refresh on tab select** for Today. **Workout** log uses **orange-filled** reference fields vs **entered** field chrome; **Done** in **bottom safe area** + **`resignFirstResponder`** (no reliance on keyboard accessory bar). **Commit after focusing** weight/reps marks **`userEditedValues`** even when values match reference.

**Subsequent logging pass:** Prior session weight/reps are **reference-only** in the UI until committed; SwiftData keeps **0/0** until commit; **Finish** deletes **`PersistedLoggedSet`** rows with **`!userEditedValues`**; running **session volume** uses entered sets only.

**Export (2026):** **Settings** → **Export program** / **Export workout history** — **`ProgramSpreadsheetExport`** / **`HistorySpreadsheetExport`**, **`MinimalXlsxArchive`** (ZIPFoundation), stamped **`Set_Buddy_Program_…`** / **`Set_Buddy_History_…`**, share sheet (**`ShareExportSheet`**). History sheets append a **`workout_total`** row per completed session (cumulative **`set_volume`**). **`HistoryRepository.allCompletedSessionDetails()`** feeds history export.

| Phase | Status | Notes |
|-------|--------|--------|
| 1 Setup | Done | SwiftUI app, tab navigation, `App` / `Presentation` / `Domain` / `Data` / `Platform`, SwiftData |
| 2 Domain & persistence | Done | SwiftData models use `Persisted*` names; repositories in `Data/Repositories/` |
| 3 Today & schedule | Done | `TodayScheduleResolver`, `ProgramCalendarSchedule`, `TodayViewModel`; **Continue** vs **Start** for in-progress vs fresh; **no Start/Continue** when today’s session is already **finished**; refresh when switching to Today tab; **September 2026:** **“Change today’s plan”** menu forces today onto a chosen workout/rest and cascades the schedule forward (`forceTodaysSchedule`) |
| 4 Workout logging | Done | `WorkoutLoggingViewModel` / `WorkoutLoggingScreen`, **kg**; **decimal / number pad**; **Done** above session volume + **`resignFirstResponder`**; **Finish** + confirmation; only **entered** sets persist |
| 5 Prior-session reference | Done | Most recent logged value **per exercise** (any workout — `mostRecentLoggedValuesByExercise`, replaced the per-workout-template `mostRecentCompletedSession`) drives **UI reference** (`SetRow`); **not** pre-seeded into store; **`userEditedValues`** + orange vs entered field chrome; focus+commit marks entry even if values match reference; **`seededFromCarryover`** unused. **September 2026:** cross-workout scoping + `ExerciseCarryoverMatcher` id-preservation at import time keeps this working across a program re-import — see Phase 7. |
| 6 Volume | Done | `VolumeCalculator`; session bar + history + detail |
| 7 Notes & import | Done | `.xlsx` via ZIPFoundation; **editable** notes on tap (log + program); import **staging sheet**: **next day in cycle** + **first calendar day** (date still in UserDefaults); default **4 sets** per exercise from import/seed; **September 2026:** staging also runs `ExerciseCarryoverMatcher` and offers a confirmable **“Carry over previous weights”** section (exact matches silent, ≥75% similar confirmable) so re-importing doesn’t sever reference-weight history |
| 8 Notifications | Done | `DailyNotificationScheduler`, `NotificationSettings` (UserDefaults), Settings UI (toggle + time) |
| 9 History | Done | List + **session detail** (sets, exercise volume) |
| 10 Program & settings | Done | Program: templates + editable schedule list (**7/14/21** days via Settings) + **Push 1 / Pull 1 / Legs 1 / …** order + in-app create / **Start over** + template CRUD; Settings: schedule length, file import → confirm sheet, notifications, “How it works”, **Export program** / **Export workout history** (`.xlsx` + `.csv` fallback, share sheet); **September 2026:** **“Version 1.0 (5)”** footer at the bottom of Settings |
| 11 Testing & stabilization | Partial | Unit tests (Swift Testing), UI tests (`-uiTesting`, in-memory store), `xcshareddata` scheme |

**Naming drift vs this document:** The codebase uses concrete types such as `PersistedProgram`, `PersistedWorkoutSession`, `PersistedLoggedSet` rather than the generic names in Phase 2 (e.g. `PlannedSet`, `LoggedExercise`). Behavior matches the plan’s intent.

## Development Objective
Build the first usable version of the app around the fastest possible path to a reliable iPhone workout logging experience with one active program, daily workout or rest-day awareness, **prior-session reference** in logging, exercise notes, notifications, and total-volume tracking.

## Delivery Priorities
1. Core data model
2. Today screen and schedule resolution
3. Workout logging flow
4. Carryover behavior
5. Total volume calculation
6. In-progress workout persistence
7. Exercise notes
8. Daily notifications
9. Basic history/progress
10. Refinement and stabilization

## Development Strategy
- Build the app in vertical slices
- Focus on the workout logging flow before secondary screens
- Keep the first release local-first and offline-capable
- Defer advanced flexibility until the core daily experience is stable
- Validate the iPhone interaction model early

## Phase 1: Project Setup

### Goals
- Initialize the iOS project
- Establish architecture skeleton
- Set up folders, targets, and base app structure
- Choose persistence strategy
- Create shared models and service protocols

### Tasks
- Create SwiftUI iOS app project
- Create directory structure for:
  - App
  - Presentation
  - Domain
  - Data
  - Platform
  - Resources
- Set up base navigation structure
- Configure SwiftData models or Core Data stack
- Create shared date and app utility helpers
- Add placeholder screens for:
  - Today
  - Workout Logging
  - Program Overview
  - History
  - Settings

### Deliverables
- Running app shell
- Architecture-aligned folder structure
- Base navigation working
- Persistence framework selected and initialized

## Phase 2: Core Domain and Persistence

### Goals
- Define all primary entities
- Implement repositories
- Enable local storage of programs, workouts, sessions, and settings

### Tasks
- Create models for:
  - Program
  - ScheduledDay
  - Workout
  - WorkoutExercise
  - Exercise
  - PlannedSet
  - WorkoutSession
  - LoggedExercise
  - LoggedSet
  - NotificationSettings
- Implement repository interfaces and concrete local repositories
- Add seed/test data support for development
- Create basic CRUD operations for active program loading and workout sessions
- Validate persistence of in-progress sessions

### Deliverables
- Working local model layer
- Repository-backed data access
- Test data available for UI development

## Phase 3: Today Screen and Schedule Resolution

### Goals
- Correctly determine whether today is a workout or rest day
- Surface today’s state in the UI
- Provide an entry point into the current workout

### Tasks
- Implement TodayScheduleService
- Build TodayViewModel
- Render workout day and rest day states
- Detect existing in-progress session for the current day
- Add CTA to start or resume workout
- Ensure one active program is loaded and respected

### Deliverables
- Functional Today screen
- Accurate daily schedule resolution
- Ability to start or resume today’s session

## Phase 4: Workout Logging Flow

### Goals
- Build the core workout screen
- Make set entry fast and usable on iPhone
- Persist changes reliably

### Tasks
- Build WorkoutLoggingViewModel
- Build WorkoutLoggingScreen
- Create reusable ExerciseCard and SetEntryRow components
- Add weight and reps inputs optimized for phone (large numeric keypads, not QWERTY)
- Implement immediate or near-immediate save behavior
- Show ordered exercises and sets
- Add lightweight workout completion action
- Preserve session state during app interruptions

### Deliverables
- End-to-end workout logging flow
- Fast per-set entry on iPhone
- In-progress data retained during interruptions

## Phase 5: Carryover Values

### Goals
- Seed new workout sessions with prior values where appropriate
- Make carryover visually obvious
- Preserve clear distinction between seeded and edited values

### Tasks
- Implement CarryoverService
- Define carryover sourcing rules
- Add set-level carryover flags to view state
- Apply light shaded styling to carryover fields
- Mark edited carryover values appropriately
- Test carryover behavior across repeated sessions

### Deliverables
- Working carryover seeding
- Clear visual carryover treatment
- Correct behavior after user edits

**As-built evolution:** Prior values are **not** written into SwiftData when a session starts. **`WorkoutSessionRepository`** creates **zero** weight/reps per set; **`WorkoutLoggingViewModel`** reads **`mostRecentLoggedValuesByExercise`** (September 2026; replaced the per-workout-template **`mostRecentCompletedSession`**) for **reference** display. **`WorkoutSetRowView`** sets **`markUserEntry`** when the user **focused** weight or reps and commits (including **same values as reference**), or when parsed values differ from reference without snapshots. **`completeWorkout`** removes non-entered rows. (Original “seed into store” / **`seededFromCarryover`** path was replaced by this model.)

**September 2026 addendum — a second, distinct “carryover”:** the original Phase 5 scope (seeding a **session**’s fields from the prior session, abandoned above) is not the same thing as the carryover added in September 2026, which operates at **import time**: `ExerciseCarryoverMatcher` matches the new workbook’s exercises against the program being replaced **by name** and preserves the matched exercise’s **id**, so the reference-lookup mechanism above (which is keyed by exercise id) keeps finding history across a re-import instead of losing it to a freshly generated id. See Phase 7 and requirements §16.

## Phase 6: Total Volume Tracking

### Goals
- Compute and display total volume accurately
- Make total volume the main progress signal in the initial version

### Tasks
- Implement VolumeCalculationService
- Compute set volume as weight × reps
- Aggregate to exercise-level volume
- Aggregate to workout-level volume
- Display running workout total in the logging screen
- Save session totals if needed for history performance

### Deliverables
- Accurate volume calculations
- Workout-level total volume visible
- Exercise-level volume support if included

## Phase 7: Exercise Notes and Import Support

### Goals
- Support imported exercise note content
- Reveal notes only on demand
- Establish import pipeline for initial program setup

### Tasks
- Define import DTOs
- Create ImportFileParser
- Create ProgramImportValidator
- Create ProgramImportService
- Map imported program structure into local entities
- Support note-column import
- Add exercise-name tap behavior to **open a note editor** (view + edit + save)
- Build note UI as a sheet (`ExerciseNoteEditorSheet`)

### Deliverables
- Program import pipeline
- Exercise note support (import + user edits persisted on `PersistedExercise`)
- On-demand note editing from workout and program screens

## Phase 8: Notifications

### Goals
- Deliver one daily notification
- Distinguish workout-day and rest-day messaging

### Tasks
- Create NotificationSettings model and settings UI
- Implement LocalNotificationManager
- Implement NotificationScheduleService
- Request notification permissions
- Schedule daily notification based on user preference
- Generate different content for workout days vs rest days
- Test scheduling edge cases and day transitions

### Deliverables
- Daily notification support
- Rest-day message support
- Configurable notification timing

## Phase 9: History and Progress

### Goals
- Provide a simple history view focused on total volume
- Let the user review recent completed sessions

### Tasks
- Build HistoryViewModel
- Build History screen
- Show recent workout sessions
- Show workout dates and total volume
- Add lightweight exercise or workout drill-down if feasible
- Ensure completed sessions appear correctly after workout completion

### Deliverables
- Basic history/progress screen
- Recent workout volume visibility

## Phase 10: Program Overview and Settings Refinement

### Goals
- Add supporting screens needed for a complete usable first release
- Improve management and clarity of active program and app preferences

### Tasks
- Build ProgramOverviewScreen
- Show active program structure and schedule
- Show workout-day and rest-day mapping
- Finalize Settings screen for notifications and general app behavior
- Ensure active program assumptions are reflected clearly in the UI

### Deliverables
- Program overview screen
- Usable settings screen
- Better end-to-end product completeness
- **As-built:** spreadsheet **export** from Settings (program workbook aligned with import; full history with per-session **`workout_total`** row)

## Phase 11: Testing and Stabilization

### Goals
- Eliminate core flow bugs
- Improve reliability and usability
- Validate interruption handling and daily use cases

### Tasks
- Test app launch on workout day and rest day
- Test start, resume, and complete workout flows
- Test **reference vs entered** logging (commit after focus persists even when values match reference; finish prunes non-entered rows)
- Test total volume calculations
- Test note reveal behavior
- Test notification scheduling and message correctness
- Test import validation and bad-input handling
- Spot-check **Settings export** (program `.xlsx` opens in Numbers/Excel; history includes **`workout_total`** rows per session)
- Test persistence across app relaunches
- Test small-screen layout behavior on target iPhone sizes

### Deliverables
- Stable release candidate
- Reduced UI and data integrity bugs
- Confidence in daily use reliability

**Automated (as-built):** `Set BuddyTests` (Swift Testing) — schedule, volume, import errors, notification prefs, template display sort, `HistoryRepository` / `ProgramOutlineRepository` with in-memory SwiftData, bundled `.xlsx` parse; **September 2026:** `WorkoutSessionRepository` set-count sync + per-side propagation + `updateLoggedSet`/`completeSession`, `WorkoutTemplateEditorViewModel`, `TodayViewModel.forceTodaysSchedule`, xlsx export round-trip, `StringSimilarity` / `ExerciseCarryoverMatcher` + an end-to-end re-import carryover test (~45 tests total). Suite runs `@Suite(.serialized)` — Swift Testing's default parallel execution isn't safe with this many tests each creating their own in-memory `ModelContainer`. `Set BuddyUITests` — tab smoke, Program/Settings, Today → Finish → History, **Today hides Start after finish**, **Today shows Continue when workout in progress**, history detail, `-uiTesting` launch flag (skips notification prompt + in-memory SwiftData); 6 of 8 pass — `testProgramTabShowsSeededProgramAndWorkouts` / `testHistoryOpensSessionDetailWithSetRows` are known pre-existing failures (confirmed via A/B against pre-refactor code), not yet fixed. Shared scheme: `Set Buddy.xcodeproj/xcshareddata/xcschemes/Set Buddy.xcscheme`.

**Install package:** `scripts/archive_and_export_ipa.sh` → auto-bumps the build number, then `build/ipa/Set Buddy <version> (<build>).ipa` (Development export; see script header). **Ad Hoc:** `scripts/archive_and_export_production_ipa.sh ad-hoc` → `build/ipa-adhoc/Set Buddy <version> (<build>) ad-hoc.ipa` (see script header). **Device install (command line):** `xcrun devicectl device install app --device <name> <path-to-.app>` then `xcrun devicectl device process launch --device <name> <bundle-id>` — used to sideload straight from this session onto a paired iPhone without Xcode's Devices window.

## Suggested Milestones

### Milestone 1
App shell, architecture skeleton, persistence foundation

### Milestone 2
Today screen and schedule resolution working

### Milestone 3
Workout logging end to end with persistent sessions

### Milestone 4
Prior-session **reference** in the log UI, **entered-only** persistence on finish, and total volume fully working

### Milestone 5
Import, notes, notifications, and history complete

### Milestone 6
Stabilization and release preparation

## Recommended Build Order for Fastest Value
1. Project setup
2. Core models and persistence
3. Today screen
4. Workout logging
5. In-progress session persistence
6. Prior-session reference (UI) + entered-set persistence
7. Volume totals
8. Notes
9. Notifications
10. History
11. Program overview
12. Stabilization

## Key Technical Decisions to Lock Early
- SwiftData vs Core Data → **SwiftData** (chosen)
- Exact schedule representation → **`PersistedScheduleEntry` + `ProgramCalendarSchedule`**
- Prior-session **reference** sourcing → **Most recent logged value for that exercise, any workout** (read in **`WorkoutLoggingViewModel`** via `WorkoutSessionRepository.mostRecentLoggedValuesByExercise`, not copied into new session rows at create time; September 2026 — widened from “same workout template” so `ExerciseCarryoverMatcher`-preserved exercise ids keep surfacing history across a program re-import)
- Whether workout totals are computed live only or also persisted → **Computed from `PersistedLoggedSet`** (log screen **session** total: **entered** sets only; History unchanged)
- Import file format and parsing strategy → **`.xlsx`** (ZIPFoundation), `ProgramXlsxParser` / `ProgramXlsxImporter`
- Export → **`Data/Export`** minimal OOXML write + CSV; `SettingsViewModel` + `ShareExportSheet`
- Note presentation pattern → **Sheet** (`ExerciseNoteEditorSheet` in `ExerciseNoteSheet.swift`)
- Units → **kg** only in UI; import/seed default **4 sets** per exercise
- Program template list order → **`WorkoutTemplateDisplaySort`** (Push 1, Pull 1, Legs 1, …)
- Import cycle alignment → **`cycleStartIndex`** on `ProgramXlsxImporter` (user picks “next” worksheet day)
- Notification scheduling strategy → **`DailyNotificationScheduler`** + `NotificationSettings` (UserDefaults); single fire-and-forget entry point **`requestReschedule(modelContext:)`** (September 2026)
- Missed-day schedule realignment → **shift-by-one cascade** from the forced day forward (**`setScheduleDayShiftingFollowing`**), surfaced on **Today** as well as the Program tab (September 2026)
- Exercise identity across a re-import → **name matching** (**`ExerciseCarryoverMatcher`**): exact auto-applies, **≥ 0.75** Levenshtein similarity (**`StringSimilarity`**) asks for confirmation, below that starts fresh (September 2026)
- Build number tracking → **`CURRENT_PROJECT_VERSION`** auto-bumped by the archive scripts (**`agvtool`**, all targets); shown in-app and baked into exported `.ipa` filenames so a build shared with friends can be matched back to what was archived (September 2026)

## Risks and Mitigations

### Risk: Workout logging feels slow on iPhone
Mitigation:
- Build and test the workout screen early
- Favor large tap targets and simple controls
- Reduce modal flows and excess navigation

### Risk: Reference vs entered confuses users
Mitigation:
- Keep sourcing rules simple (last **completed** session for template)
- Make **reference** visually obvious (orange reference fields vs entered styling)
- Track **`userEditedValues`** and prune non-entered rows on finish

### Risk: Persistence bugs lose workout progress
Mitigation:
- Save often during entry
- Test interruption and relaunch scenarios early
- Keep session state model straightforward

### Risk: Notification trust is damaged by incorrect daily status
Mitigation:
- Centralize date and schedule logic
- Reuse the same schedule service for UI and notification content
- Test around midnight and weekday boundaries

### Risk: Import becomes too broad too early
Mitigation:
- Support only required fields in v1
- Validate strictly
- Defer optional complexity

## Definition of Done for First Release
The first release is done when:
- One active program can be loaded and used
- The app correctly shows workout day or rest day
- The user can start and resume workouts
- The user can log weight and reps quickly on iPhone
- **Reference** (prior session) vs **entered** values are shown with distinct styling; only **entered** sets persist on finish
- Exercise notes can be imported and edited on tap (workout + program)
- Total volume is calculated and visible
- Daily notifications work for both workout days and rest days
- A simple history/progress view is available
- Core flows remain stable across relaunches and interruptions
- Program and history can be exported to spreadsheets from Settings

**Release hygiene (outside this plan):** App Store assets, signing, privacy labels, and full manual Phase 11 passes remain operator tasks.

## Post-Release Candidates
- Multiple programs
- Richer analytics
- PR estimation or trend insights
- Apple Watch support
- Cloud sync
- Richer export (e.g. importable history, PDF, cloud destinations)
- More advanced scheduling logic
- Widgets and lock screen surfaces

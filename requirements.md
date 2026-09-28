# Requirements Document

## Project Name
Set Buddy

## Purpose
Build an iPhone-first fitness tracking app optimized for fast workout logging during gym sessions. The product should emphasize minimal friction, quick set entry, clear visibility of **prior workout values as reference** (distinct from **new** entries), and simple daily guidance on whether the user should train or rest.

## As-built alignment
This document states **product requirements**. The current app **implements** the first-release scope below with these concrete behaviors (see `architecture.md` for file/type names):

- **Single program:** User may **create** a program in-app or **import** `.xlsx`. Import or **Start over** replaces program + schedule; **completed** sessions remain in History; in-progress session cleared.
- **Import:** `.xlsx` only; after file pick, user chooses **which worksheet day in the cycle is next** and the **first calendar day** that maps to it (start date persisted in UserDefaults); worksheet tab order = day cycle; row-1 headers can label **Notes** and **Per side** columns (order flexible); rest via empty sheet or sheet name containing “Rest”. When a program is already active, exercises in the new workbook are matched **by name** against it: exact matches keep their reference-weight history automatically, close (≥75%) matches are offered for the user to confirm before being carried over, and unmatched exercises start fresh (no history to carry).
- **Units:** Weight is shown and entered in **kg** (no lb in UI).
- **Default sets:** New/imported exercises default to **4** sets unless the spreadsheet implies otherwise; **in-app**, each exercise’s **`setCount`** can be edited within **1…20** (`ProgramRepository`).
- **Notifications:** Daily local notification; user can **disable** reminders and set **time of day**; permission prompt skipped when running with `-uiTesting`.
- **History:** List shows completed sessions + volume; **navigation** to per-session **detail** (sets, exercise names, totals).
- **Program screen:** Template workouts/exercises (**Push 1 / Pull 1 / Legs 1 / …** order when those names exist), full in-app editing (parity with importable fields), and **upcoming schedule** rows for **7, 14, or 21** days from today (setting in **Settings → Program**, default 14) + short copy.
- **Today:** If the user has **already completed** today’s scheduled workout, the **Start** / **Continue** action must not appear (progress lives in History). If today’s workout is **in progress**, the app should surface **Continue** (or equivalent) rather than implying a fresh **Start** only.
- **Workout log:** Prior session weight/reps appear for **reference** with strong visual distinction from **entered** data (e.g. filled orange reference fields vs committed-entry styling); **only entered** set data is **persisted** when the workout is finished (reference-only rows are not saved). Reference values are found by **exercise identity** (any workout that logged that exercise), not restricted to the current workout template — see **Import** and **Schedule realignment**, below.
- **Schedule realignment:** If the user misses a scheduled day (e.g. travel), the **Today** screen offers a **“Change today’s plan”** control to force today onto whatever workout (or rest) they're actually doing; the rest of the schedule shifts forward by one day so the workout rotation's order stays correct without the user re-entering every missed day by hand.
- **Export:** **Settings → Export** offers **Export program** and **Export workout history**. The app prefers **`.xlsx`** and falls back to **`.csv`** if workbook generation fails. File names use **`Set_Buddy_Program_yyyy-MM-dd_HHmmss`** and **`Set_Buddy_History_yyyy-MM-dd_HHmmss`**, then the **system share sheet** (temporary files are removed after sharing). Program **`.xlsx`** matches import layout (**one sheet per workout**, `Exercise_Name` / `Notes` / `Per side`, workouts ordered like the Program tab). Program **`.csv`** includes program/workout/exercise rows (including **`set_count`**) plus **schedule** rows (`schedule_date`, rest/workout, workout name). History export is one row per **logged set** (completed time, workout, schedule day, totals, exercise, set #, weight, reps, per-side, set volume); after each **completed session**’s set rows, a **`workout_total`** row gives the **cumulative set volume** for that session (detail columns left blank).

## Product Goals
- Allow the user to log workouts quickly on an iPhone while actively training.
- Display the current day's workout clearly with minimal clutter.
- Support one active workout program at a time.
- Make previous workout values easy to see and re-type or adjust (reference in UI; persistence only for what the user enters).
- Track total volume as the main progress metric in the first version.
- Provide a daily notification that indicates either the scheduled workout or a rest day.

## Non-Goals
- Multiple active programs
- Advanced analytics beyond total volume
- Social features
- Wearables integration
- Coach or multi-user support
- Exercise video libraries
- Importing target reps
- Complex custom gestures or advanced data-entry patterns

## Target Users
- Individual lifters using an iPhone during workouts
- Users who want very fast logging with minimal taps
- Users who train on a recurring schedule and want a lightweight daily workflow

## Platform
- iOS
- iPhone-first
- Tablet optimization is not required for the initial release
- **Android** (added 2026-09-12; feature parity with iOS reached 2026-09-16): native Jetpack Compose app, phone-first, sharing scheduling/volume/carryover logic and the persistence schema with iOS via a Kotlin Multiplatform `shared` module. `.xlsx` import/export, program/exercise editing, notes, and volume tracking are all ported — see `architecture.md` and `development_plan.md`. Not yet done: linking the shared module into the Xcode/iOS build.

## Core Experience Principles

### Speed First
The app must minimize taps and reduce time spent interacting with the screen during workouts.

### Small-Screen Clarity
Layouts must be easy to scan and interact with on iPhone screens in a gym environment.

### Reference vs entered (prior session)
Values shown from the **prior completed** workout should be visually distinguishable from **new** entries (e.g. high-contrast field treatments such as orange-filled reference fields vs a different style once committed). **Persistence** should reflect **only** what the user commits for the current session, not a silent copy of reference data.

### Progressive Disclosure
Secondary information should stay hidden until needed, including exercise notes.

## Functional Requirements

### 1. Program Management
- The app must support exactly one active training program at a time.
- A program must include:
  - Program name
  - Scheduled workout days
  - Scheduled rest days
  - Workouts
  - Exercises
  - Set structure
  - Optional exercise notes imported from source data

### 2. Daily Workout Status
- The app must determine whether the current day is:
  - A workout day, or
  - A rest day
- If it is a workout day, the app must display the scheduled workout.
- If it is a rest day, the app must clearly indicate that no workout is scheduled.

### 3. Today Screen
The Today screen must show:
- Today's status
- Scheduled workout or rest day
- Fast entry point into the current workout **when it has not already been completed today**
- When today’s scheduled workout is **already in progress**, the entry point should read as **resume** (e.g. **Continue**), not only as a fresh **Start**

**As-built:** **`TodayViewModel`** uses **`WorkoutSessionRepository.activeSession`** to set **`workoutInProgress`**; **`TodayScreen`** refreshes when the **Today** tab is selected.

### 4. Workout Logging
The workout logging flow must:
- Show the workout name
- Show exercises in order
- Show each exercise's sets
- Allow entry of:
  - Weight
  - Reps
- Support fast per-set logging on iPhone

### 5. Input Controls
- Weight and reps must use **system numeric entry** (large **number-style** keypads—not the full QWERTY keyboard). **+/- steppers are not used.**
- A clear way to dismiss the keyboard and commit values is required (on-device number pads may not show a system accessory bar when fields live inside a list).
- Controls must be easy to use quickly during a workout.
- The design should favor repeated efficient entry over complex interaction models.

**As-built:** Decimal pad for weight (kg), number pad for reps; **Done** in the bottom chrome (above session volume) commits and dismisses the keyboard via **`resignFirstResponder`**; **Finish** also dismisses the keyboard before the completion dialog.

### 6. Prior-session reference (workout log)
- The app must show prior workout weight/reps **per set** (from the last **completed** session for that workout template) as **reference** when starting today’s log.
- Reference values must be **visually distinct** from entered values (e.g. orange-filled weight/rep fields vs a distinct “committed” field style).
- **Only** values the user **commits** during the current session are **stored** on finish; reference-only rows must not be persisted as if they were new data.
- Once the user has committed a set (including confirming the same numbers as reference after focusing a field), it should read as **current-session** styling.

### 7. Exercise Notes
- The app must support importing an exercise note column.
- Notes should not dominate the main workout view.
- If the user taps the exercise header/name, the user must be able to **view, add, and edit** the note and save it back to the exercise.

**As-built:** **`ExerciseNoteEditorSheet`** from workout logging and Program tabs; persisted on **`PersistedExercise.note`**.

### 8. Progress Tracking
- Total volume is the primary progress metric for the first version.
- Total volume must be computed from logged set data.
- At minimum, total volume should be calculated as weight × reps, aggregated appropriately.
- The app should display total volume in workout summaries and any basic history/progress surfaces included in the initial version.

**As-built:** Running **session** total on the log screen; history list and session detail show aggregates.

### 9. Notifications
- The app must provide a notification every day (when enabled and authorized).
- On workout days, the notification should remind the user about the scheduled workout.
- On rest days, the notification should explicitly state that it is a rest day.

**As-built:** User can turn off daily scheduling and set clock time in Settings; scheduling uses the same calendar logic as Today (14-day horizon of pending requests).

### 10. Data Import
The initial import process must support:
- Program structure
- Workout structure
- Exercise list
- Set structure needed by the app
- Exercise notes

The initial import process does not need to support:
- Target reps import

**As-built:** `.xlsx` via Settings file picker → **confirmation sheet** with **next day in cycle** picker + **first calendar day**; import builds a forward **horizon** with **`cycleStartIndex`** alignment (see `ProgramXlsxImporter`).

### 11. History and Progress
The app should include a basic history/progress area focused on total volume.
The initial version should prioritize:
- Workout-level total volume
- Simple exercise or workout history if feasible

Advanced analytics are out of scope for the first release.

**As-built:** **Session detail** screen with per-exercise sets and volumes satisfies “if feasible.”

### 12. In-Progress Workout State
- The app must preserve in-progress workout data if the session is interrupted.
- The user must be able to resume an incomplete workout without losing entered values.

### 13. Workout Completion
- The user must be able to complete a workout after logging all desired sets.
- Completion behavior should be lightweight and should not add unnecessary friction.

**As-built:** **Finish** (with confirmation) saves **`workoutTitleSnapshot`**, **`completedAt`**, and **`isComplete`**; **removes** any **`PersistedLoggedSet`** that was never user-entered (`!userEditedValues`) so History only contains **entered** sets. Dialog copy states that only entered sets are saved.

### 14. Spreadsheet export (as-built)
- The user must be able to export the **current program** and **full workout history** from Settings for backup or analysis.
- Export formats: **`.xlsx`** when possible, **`.csv`** as fallback; filenames include **date and time** (see **As-built alignment** at the top of this document).
- History exports list every **logged set**; after each **completed session**’s set rows, a **summary row** (`exercise` = `workout_total`) carries the **cumulative `set_volume`** for that session (other detail columns empty).

### 15. Schedule Realignment (as-built)
- If the user misses one or more scheduled days, the app must let them realign the schedule from the **Today** screen rather than requiring a trip to the Program tab.
- Forcing today onto a different workout (or rest) than currently scheduled must shift every later scheduled day forward by one day, preserving the relative order of the workout rotation, so the user only has to act on **today** — not on each day they missed.

**As-built:** **`TodayViewModel.forceTodaysSchedule(to:)`**, surfaced via the **“Change today’s plan”** menu on **`TodayScreen`**; reuses **`ProgramRepository.setScheduleDayShiftingFollowing`**, the same cascade the Program tab’s per-day schedule menu already used.

### 16. Exercise Carryover on Import (as-built)
- Re-importing a program (replacing the active one) must not silently discard the ability to see prior weights for exercises that are still part of the new program.
- The app must match exercises between the program being replaced and the newly imported workbook **by name**.
- **Exact** name matches (case/whitespace-insensitive) must carry over automatically, without user interaction.
- **Close but not exact** name matches must be presented to the user to confirm or reject before being carried over.
- Exercises with no reasonable match must be treated as new (no history to carry).

**As-built:** **`ExerciseCarryoverMatcher`** (exact pass, then greedy best-score assignment for matches `>= 0.75` similarity via **`StringSimilarity`**’s Levenshtein ratio) runs when a file is picked (**`ImportViewModel.stageImportFromPickedFile`**); suggestions appear as pre-checked toggles in a **“Carry over previous weights”** section on the import staging sheet. Confirmed matches are passed to **`ProgramXlsxImporter.importReplacingStore(..., exerciseCarryover:)`**, which reuses the old exercise’s id so **`WorkoutSessionRepository.mostRecentLoggedValuesByExercise`** keeps finding its logged history.

### 17. Cardio Exercises (as-built)
- The user must be able to mark an exercise as **cardio** instead of strength, both as a standalone workout day (e.g. a dedicated "Cardio" day, alongside Push 1/Pull 1/Legs 1/Rest) and as one exercise within an otherwise-strength workout (e.g. finishing a lifting session with a cardio set).
- Cardio sets must track **total minutes** and **max heart rate** instead of weight/reps.
- Cardio sets must follow the same reference-value carryover, only-entered-sets-are-saved, and set-count behavior as strength sets — no separate interaction model.
- Cardio sets must not contribute to weight × reps volume; History and exports must still record their minutes/max heart rate.

**As-built:** **`ExerciseKind`** (`.strength` / `.cardio`) on **`PersistedExercise`**, set via a **Strength/Cardio** segmented control in the workout template editor (replaces the "Per side" toggle for cardio exercises). A "Cardio day" is just a normal workout template made up of cardio exercises — no separate schedule-day concept was needed since **`ScheduledDayKind`**/the workout picker already accept any named workout. **`PersistedLoggedSet`** gained `cardioMinutes`/`maxHeartRate` fields alongside the existing `weight`/`reps`; **`WorkoutLoggingScreen`** renders **Minutes**/**Max HR (bpm)** fields (same reference/entered chrome as weight/reps) when the exercise's section is cardio, via a parallel **`WorkoutCardioSetRowView`**. History and both spreadsheet exports (program `Type` column; history `type`/`cardio_minutes`/`max_heart_rate` columns) carry the new fields; volume calculations skip cardio sets. `.xlsx` **import** (2026-09-28, second pass) also recognizes cardio: a row reading **Minutes** / **Peak HR** (or a close synonym — see `ProgramXlsxParser.cardioSectionHeaderRow`) marks the start of a cardio section on a sheet — every exercise name below it, to the end of that sheet, imports as cardio. A sheet can be a normal strength day that finishes with a cardio section (one exercise, e.g. a treadmill set after lifting), or be cardio-only from the first row (a whole cardio day).

## User Interface Requirements

### Workout Logging Screen
The workout logging screen must be the primary operational screen and should:
- Be optimized for iPhone use
- Prioritize readability and quick entry
- Surface **reference** (prior session) vs **entered** values clearly
- Make weight (kg) and rep entry fast via numeric keypads
- Allow **note edit** by tapping exercise section headers

### Usability
- Controls must be large enough for gym use
- Common actions must not require deep navigation
- The app should avoid unnecessary confirmations during normal logging flow

## Minimum Screen Set
The first release should include:
- Today screen
- Workout logging screen
- Program overview or schedule screen
- History/progress screen
- Basic settings screen

**As-built:** Five tabs in `MainTabView` (Today, Workout, Program, History, Settings). **Settings** includes **Export program** and **Export workout history** (see section 14), and a **version/build number footer** (“Version 1.0 (5)”) for troubleshooting builds shared with other people — the same number is baked into the archive scripts' exported `.ipa` filenames.

## Open Requirement
Earlier drafts referenced a single unresolved product decision. **No such item blocks the current v1 feature set** documented here. If a new decision is introduced (e.g. multi-program), requirements and import behavior should be updated explicitly.

## Success Criteria
The first release is successful if:
- The user can immediately see whether today is a workout day or rest day
- The user can log a full workout quickly from an iPhone
- Prior-session **reference** values make repeated workout entry easier without silently duplicating old data in storage
- Exercise notes are available on demand (sheet editor) without cluttering the main list UI
- Daily notifications correctly reflect workout or rest-day status (when enabled)
- Total volume is reliably tracked and visible as the main progress metric
- The user can export the active program and completed workout history to spreadsheets when needed
- Missing a scheduled day doesn't require manually re-fixing the whole calendar — forcing today's plan on the Today screen realigns the rest of the rotation automatically
- Re-importing an updated program doesn't erase the ability to see prior weights for exercises that carried over from the old one

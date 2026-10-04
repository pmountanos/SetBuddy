# Context Document

## Project Name
Set Buddy

## Project Type
Native iOS application focused on workout logging and daily training guidance. As of 2026-09-16, also has a **native Android build** (Jetpack Compose) at feature parity with iOS, sharing its scheduling/volume/carryover business logic and persistence schema via a Kotlin Multiplatform module — see **Android** below and `architecture.md`.

## Project Summary
This project is an **iPhone-first** fitness app for fast use during gym sessions. A single user follows **one** active program, sees **workout vs rest** for the current calendar day, and logs **weight and reps**. The **most recently logged** value for that **exercise** (tracked by exercise identity, not tied to a specific workout template — see **Import carryover**, below) supplies **reference** weight/reps in the log UI (**orange-filled** weight/rep fields with white text); after the user **commits** a set (same numbers or edited), fields switch to a **high-contrast filled** style for **today’s** entry. **Only values the user commits** are stored—finishing drops any set row that was never entered. **Total volume** (weight × reps) is the main progress signal (running total on the log screen counts **entered** sets only). **Exercise notes** (e.g. from spreadsheet column B) are **on demand** via a sheet. **Local notifications** remind daily when enabled. Re-importing a program **matches exercises by name** against the one being replaced so reference weights and history aren't lost, and **missing a day** can be fixed from Today by forcing that day onto the workout you actually want, which realigns the rest of the schedule automatically.

The first version is intentionally narrow: not social, not a coaching platform, not deep analytics. It is optimized for **repeated daily use** on a phone in a gym.

## Problem Being Solved
Many trackers are too slow or cluttered for real-time lifting. This app reduces friction: immediate daily status, fast set entry, visible **last-session reference** values, and simple volume history.

## Product direction (as-built)
- Fast workout logging: **weight (kg)** and **reps** via **large numeric keypads** (decimal pad / number pad). A **Done** control in the **bottom bar** (above session volume) commits values and dismisses the keyboard—number pads do not show a system keyboard accessory reliably inside `List`. **Finish** also dismisses the keyboard before the completion dialog.
- Clear **Today** status (workout title, rest, no program, or day outside stored schedule). Selecting the **Today** tab **refreshes** status from SwiftData. If an **in-progress** session exists for today’s scheduled workout, the screen shows **Continue {title}** instead of **Start**. If today’s planned workout is **already finished**, **Start** / **Continue** are hidden (session remains in History). A **“Change today’s plan”** menu (Rest + every workout) lets the user **force today onto a different workout** — e.g. after missing a day while traveling — which cascades every later scheduled day forward by one so the workout rotation's order stays correct without having to fix each missed day by hand.
- **One** active program; user can **create** a starter program in-app (no import required) or **import** `.xlsx` (replaces program + schedule); **Start over** on the Program tab matches import rules for History (completed sessions kept, in-progress cleared). **History** keeps completed sessions.
- **Reference** weight/reps from the most recently logged **completed** set for that exercise, **any workout** (see **Import carryover**) in the log UI (orange fields); **committed** values use the **entered** field style; committing after focusing weight or reps counts as entry **even when values match reference** (so reference styling clears without forcing a dummy edit). **Finish** saves **only** sets the user committed—not silent reference copy.
- Volume on the log screen, in **History**, and in **session detail** (history shows **kg**); cardio sets don't count toward it.
- **Cardio exercises** (as of 2026-09-28): an exercise can be marked **Strength** or **Cardio** in the workout template editor. Cardio sets log **minutes** and **max heart rate** instead of weight/reps, with the same reference-value/entered-value styling and only-committed-sets-are-saved rule. A dedicated cardio **day** (e.g. "Cardio" alongside Push 1/Pull 1) is just a normal workout made of cardio exercises — no separate scheduling concept. **`.xlsx` import** also recognizes cardio: a row reading **Minutes** / **Peak HR** marks where a cardio section starts on a sheet, so a spreadsheet can finish a lifting day with a cardio set or dedicate a whole tab to cardio.
- **Program** tab: workout/exercise outline sorted **Push 1 → Pull 1 → Legs 1 → Push 2 → …** when those names exist; editable templates and an **upcoming schedule** list of **7, 14, or 21** days (choice in **Settings → Program**, default 14).
- **Settings:** “How it works,” **notifications** (toggle + time + permission helpers), **upcoming schedule list length**, `.xlsx` import: after file pick, a sheet to choose **next workout in workbook cycle** and **first day on calendar** (start date still persisted in UserDefaults), plus — when a program already exists — a **“Carry over previous weights”** section matching the new workbook's exercises against the current program **by name**: exact matches carry over silently, close (≥75% similar) matches are shown as pre-checked toggles to confirm or reject. **Export:** **Export program** / **Export workout history** — prefers **`.xlsx`**, falls back to **`.csv`**; stamped names `Set_Buddy_Program_yyyy-MM-dd_HHmmss` and `Set_Buddy_History_yyyy-MM-dd_HHmmss`; **share sheet**; temp file deleted after dismiss. Program **`.xlsx`** matches import (one sheet per workout, `WorkoutTemplateDisplaySort`). Program **`.csv`** adds structured exercises (**`set_count`**) and **schedule** rows. History **`.xlsx`/`.csv`**: one row per logged set; each **completed session** ends with **`workout_total`** and cumulative **`set_volume`**. A **version footer** (“Version 1.0 (5)”) sits below Export, sourced from the same build settings the archive scripts use to name exported `.ipa` files — see **Core decisions**.

## Android (feature parity with iOS as of 2026-10-04)
The Android app (`androidApp/`, package `net.mountanos.setbuddy`) is now at feature parity with iOS: program creation (in-app or `.xlsx` import, with staging + exercise carryover), Today status with "Change today's plan", Workout Logging with reference values, session volume, and exercise/session notes, a Program tab with full workout/exercise editing (rename, reorder, set count, per-side, delete) and a schedule-day menu, History with per-row/per-detail/per-exercise volume and editable session notes, and Settings matching iOS section-for-section (How it works, notifications, schedule-length + import, export). Daily reminders use Android's own permission model (`POST_NOTIFICATIONS` + the OS's "Alarms & reminders" special access for exact alarms), which is a one-time user grant like iOS's notification permission prompt. Export shares files via a `FileProvider` + Android's share-sheet chooser (the `ACTION_SEND` equivalent of iOS's `UIActivityViewController`). As of 2026-10-04 it also has everything iOS gained after that port: **cardio exercises** (Strength/Cardio in the workout editor, minutes + max heart rate logging, cardio sections in `.xlsx` import, cardio columns in both exports), workouts listed in **spreadsheet cycle order**, the **bounded schedule cascade** (pulling an upcoming workout to today no longer duplicates it or delays the rest of the cycle), and **Reopen** on a finished workout. See `architecture.md` for the module layout and `development_plan.md`'s September/October 2026 entries for what's shared vs. platform-specific.

## Intended User
An individual lifter who trains on a repeating schedule, uses an iPhone at the gym, wants minimal taps, and cares about volume more than advanced analytics.

## First release scope (implemented)
- One active program
- Workout-day and rest-day detection from **persisted schedule entries**
- **Tabbed UI:** Today, Workout, Program, History, Settings
- Weight/reps logging with **reference vs entered** styling (orange reference fields; committed-entry fields)
- Exercise **note import** + **editable** note sheet from **exercise header/name** tap (log + program); stored on `PersistedExercise.note`
- Daily **local** notifications (configurable)
- Total volume in session, history list, and detail
- In-progress session persistence (SwiftData)
- **`.xlsx` import** with user-chosen **cycle phase** (which worksheet day is next) and **first calendar day** mapping
- **History drill-down** (sets per exercise)
- **Spreadsheet export** (program + full history from Settings; `.xlsx` with `.csv` fallback)

Not in v1 (still valid):
- Multiple active programs, cloud sync, wearables, social, coach flows, target-reps import, exercise media.

## Core decisions (as-built)

| Topic | Decision |
|--------|-----------|
| Program count | One active program |
| Schedule | `PersistedScheduleEntry` rows; `ProgramCalendarSchedule` for resolution |
| Prior session in UI | Most recent logged value for that **exercise** (any workout template — see **Import**, below) → **reference** fields in **`WorkoutLoggingViewModel`** (not pre-seeded into SwiftData); orange vs entered field chrome in **`WorkoutLoggingScreen`** |
| Schedule realignment | Missed a day? **Today → “Change today’s plan”** forces today onto a chosen workout/rest and cascades every later day forward by one, keeping the rotation’s order correct (`TodayViewModel.forceTodaysSchedule`, same mechanism as the Program tab’s per-day menu) |
| Import carryover | New exercises matched **by name** against the program being replaced (exact → silent; ≥75% similar → user confirms) keep the old exercise’s id, so reference weights survive a re-import (`ExerciseCarryoverMatcher`) |
| Volume | `VolumeCalculator`; aggregated from `PersistedLoggedSet` |
| Notes | `PersistedExercise.note`; **`ExerciseNoteEditorSheet`** (file `ExerciseNoteSheet.swift`) — Cancel / Save |
| Import | `.xlsx`; ZIPFoundation; `ProgramXlsxParser` / `ProgramXlsxImporter` (**`cycleStartIndex`**) |
| Export | `Data/Export/` — `ProgramSpreadsheetExport`, `HistorySpreadsheetExport`, `MinimalXlsxArchive` (+ `SpreadsheetFormatting`); `SettingsViewModel` → temp file + `ShareExportSheet`; `HistoryRepository.allCompletedSessionDetails()` for history |
| Units | **kg** in UI (no lb) |
| Default sets | **4** per exercise from parser defaults and seed templates; **1…20** via **`ProgramRepository.setExerciseSetCount`** / add exercise |
| Notifications | `DailyNotificationScheduler` + `NotificationSettings` (UserDefaults) |
| History titles | `workoutTitleSnapshot` when available |
| UI tests | `-uiTesting` → in-memory SwiftData + no notification prompt |
| Build numbering | `CURRENT_PROJECT_VERSION` auto-bumped by both archive scripts (`agvtool`, all targets); `MARKETING_VERSION` stays manual — see `architecture.md` → **Versioning** |

## UX priorities
- **Speed:** few steps per set.
- **Clarity:** Today and log screens scannable in the gym.
- **Small screens:** large numeric fields and keypads for weight/reps.
- **Progressive disclosure:** notes in a sheet (editable when opened).
- **Reliability:** model saves during logging; completed sessions durable across import when designed to.

## Technical direction (as-built)
- **SwiftUI** + **MVVM** (`@Observable`)
- **SwiftData** for program, schedule, templates, sessions, logged sets
- **Repositories** under `Data/Repositories/`
- **Domain** value types and pure functions under `Domain/`
- **Platform** helpers: notifications, `DateProviding`, `UITestLaunch`
- **SPM:** ZIPFoundation

Local-first and offline-capable.

## Key screens (behavioral)
- **Today:** `ContentUnavailableView`-style status + **Start {title}** when workout day, not finished, no in-progress session; **Continue {title}** when today’s scheduled workout has an incomplete session; checkmark-style state when already done.
- **Workout:** Sections per exercise; **Finish** (only **entered** sets persist); session volume inset (**entered** sets only); prior session shown as **orange reference** fields; **note editor** sheet from section header tap.
- **Program:** Name, copy, **Upcoming schedule**, then workout sections with tappable exercises for notes.
- **History:** List → **detail** with completed date, scheduled day label, total volume, sets.
- **Settings:** How it works, notifications, program/import section, **Export** (program + history).

## Data stored
- Program, schedule entries, workout templates, exercises (incl. notes, set counts)
- In-progress and completed sessions; **logged sets** only for **entered** sets after finish (`PersistedLoggedSet.userEditedValues`)
- UserDefaults: notification prefs, import **first calendar day** preference (used in import sheet)

## Import expectations
- **Supports:** program/workout/exercise structure, default **4** set counts, notes, rest-day sheets; **cycle offset** so the next worksheet day aligns with the chosen calendar start; **exercise-name matching** against the program being replaced so reference weights carry forward (exact match silent, ≥75% similar asks for confirmation)
- **Does not:** target reps

## Export expectations
- **Program:** `.xlsx` workbook for re-import; `.csv` includes human-readable workouts (**`set_count`**, notes, per-side) plus ISO **schedule** rows
- **History:** all completed sessions (newest first in repository); **`workout_total`** row per session in the spreadsheet

## Constraints
- iPhone-first
- One program
- Local-first
- Minimal v1 breadth; speed over feature count

## Open item
No unresolved requirement blocks the documented v1. Future scope (multi-program, sync, etc.) should be specified explicitly when prioritized.

## Success definition
The project meets its goal if users can: see today’s training status immediately (including **Continue** when a session is in progress); start and complete logging quickly; see last session as **reference** and tell it apart from **entered** data without awkward workarounds; read notes when needed; get correct daily notifications when enabled; and review volume in History and session detail.

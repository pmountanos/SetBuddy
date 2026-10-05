# Requirements

These are the product requirements for Set Buddy, with a short note under each on how the app meets it. File paths are relative to `mobile/src/`. For how the pieces fit together see `architecture.md`.

## Purpose
A phone app optimised for fast workout logging during gym sessions: minimal friction, quick set entry, clear visibility of previous values as a **reference** (distinct from **new** entries), and simple daily guidance on whether to train or rest.

## Goals
- Log a workout quickly on a phone while training.
- Show the current day's workout clearly, with minimal clutter.
- Support one active program at a time.
- Make previous values easy to see and re-enter or adjust.
- Track total volume as the main progress measure.
- Send a daily notification saying whether it is a workout or a rest day.

## Non-goals
Multiple active programs, analytics beyond total volume, social features, wearables, coach or multi-user support, exercise videos, importing target reps, and complex gestures.

## Platforms
- iPhone and Android phones, from one React Native codebase.
- Phone-first. Tablet layouts are not a requirement.
- Local-first: everything works offline and nothing leaves the device unless the user exports it.

## Principles
- **Speed first.** Few taps per set.
- **Small-screen clarity.** Scannable and usable one-handed in a gym.
- **Reference versus entered.** Previous values must look different from today's entries, and only what the user enters may be stored.
- **Progressive disclosure.** Secondary information, such as exercise notes, stays hidden until asked for.

## Functional requirements

### 1. Program
- Exactly one active program, with a name, workouts, exercises, a per-exercise set count, optional exercise notes, and a schedule of workout and rest days.
- The user can create a starter program in the app or import one from a spreadsheet, and can edit every part of it in the app.
- Replacing the program (import or **Start over**) keeps completed sessions in History and clears a workout in progress.

*How:* `data/programRepository.ts`; editing UI in `ui/WorkoutEditor.tsx` and `app/(tabs)/program.tsx`.

### 2. Daily status and the Today screen
- The app determines whether today is a workout day or a rest day and shows it immediately.
- A workout day offers a fast way into logging. If today's workout is already in progress the action reads **Continue**; if it is already finished, **Start** is not offered — **Reopen** is, so a mistaken Finish can be undone with the entered sets intact.

*How:* `state/todayStatus.ts`, `app/(tabs)/index.tsx`. Status is re-read whenever the tab is shown.

### 3. Workout logging
- Show the workout's name, its exercises in order, and each exercise's sets.
- Each set takes **weight** (kilograms, decimals allowed) and **reps**.
- Entry uses the system numeric keypads, not the full keyboard, and not +/- steppers.
- There must be an obvious way to dismiss the keypad, since number pads have no Return key.
- An interrupted workout must be resumable without losing anything entered.

*How:* `ui/WorkoutLogger.tsx`. Each value is written to the database as it is typed, so nothing depends on how a field loses focus or on the app staying alive. A **Done** button in the bottom bar dismisses the keypad.

### 4. Reference values
- Each set shows the most recent logged values for that exercise as a reference when today's log starts.
- Reference values must be visually distinct from entered values.
- Only values the user enters are stored. Touching a set and leaving it unchanged counts as confirming it.
- A set that was never touched, or was entered and then cleared back to nothing, is not saved when the workout is finished.

*How:* reference lookup is by exercise identity across all completed sessions (`data/sessionRepository.ts`, `mostRecentLoggedValuesByExercise`), not tied to one workout. Orange fields are reference, high-contrast fields are entered.

### 5. Finishing a workout
- Finishing is one action with a single confirmation that states only entered sets are saved.
- The workout's name at the time is stored with the session, so History stays readable after the program is later replaced.

### 6. Exercise notes
- Notes can be imported from the spreadsheet and edited in the app.
- They do not occupy the main logging view; tapping an exercise's name opens its note.

### 7. Volume
- Total volume is weight × reps summed over entered sets, doubled for exercises marked **per side**.
- It is shown live while logging, in the History list, and in each session's detail.

*How:* `domain/volume.ts`.

### 8. Cardio
- An exercise can be marked **cardio** instead of strength. A whole cardio day is just a workout whose exercises are cardio.
- Cardio sets record **minutes** and **max heart rate**, follow the same reference and only-entered-is-saved rules, and do not count toward volume.
- Switching an exercise to cardio sets its set count to 1 (still adjustable).

### 9. Schedule
- The schedule is stored per calendar day and kept filled about 28 weeks ahead.
- The Program tab lists the next 7, 14 or 21 days (chosen in Settings; default 14) and lets the user change any day.
- **Realignment:** changing a day — from Today's **Change today's plan** or the Program tab — must keep the rotation's order. If the chosen workout is already due again within the next 60 days, the app pulls it forward and shifts only the days in between. Otherwise it inserts the workout and shifts every later day by one. **Add a rest day** always inserts.
- Deleting a workout turns the days that used it into rest days.

*How:* `ProgramRepository.setScheduleDayShiftingFollowing`.

### 10. Spreadsheet import
- Imports `.xlsx`. Each worksheet is one day of the rotation, in tab order. A sheet whose name contains "rest", or that has no exercises, is a rest day.
- Column A holds exercise names unless row 1 has headers. Recognised headers: an exercise-name column, **Notes**, **Per side** (also "Per set"), and **Type**. Without headers, column B is the note and column C the per-side marker (`x`, `yes`, `true`, `1`, `✓`).
- A row reading **Minutes** then **Peak HR** (or close synonyms) starts a cardio section: every exercise below it on that sheet is cardio.
- After picking a file the user chooses which day of the workbook comes next and which calendar day it falls on, then confirms.
- A failed import leaves the existing program untouched.

*How:* `xlsx/programXlsxParser.ts`, `data/programImporter.ts`, `ui/ImportStaging.tsx`.

### 11. Carrying history across an import
- Re-importing must not lose the reference values of exercises that are still in the program.
- Exercises are matched by name against the program being replaced: exact matches (ignoring case and surrounding spaces) carry over automatically; close matches (similarity of at least 0.75) are shown for the user to accept or reject; the rest start fresh.

*How:* `domain/carryoverMatcher.ts`. A carried-over exercise keeps its id, which is what reference lookups key on.

### 12. Export
- The user can export the current program and the complete workout history from Settings.
- `.xlsx` when possible, `.csv` as a fallback, with date-and-time-stamped file names, through the system share sheet.
- The program workbook has one sheet per workout in the layout the importer reads, so it imports back unchanged, cardio included.
- The history export has one row per logged set, followed for each session by a `workout_total` row carrying that session's volume.

*How:* `export/`.

### 13. Reminders
- When enabled and permitted, one local notification per day at a time the user chooses.
- Workout days name the workout; rest days say so.
- Reminders follow the schedule: any change to the program or schedule re-plans them.
- On Android the user is told that on-time delivery needs the system's "Alarms & reminders" permission, with a shortcut to it.

*How:* `notifications/`. The next 14 days are kept scheduled and rolled forward whenever the app is opened.

### 14. History
- A list of completed sessions with date and volume, newest first.
- Each opens to a detail view: every exercise, every set, per-exercise totals, and an editable workout note.

### 15. Upgrading from the earlier native apps
- Installing this app over the earlier native iOS or Android app must keep the user's program, schedule and history.

*How:* `data/appDatabase.ts` on first launch. On Android the old database file has the same schema and is adopted as is. On iOS the old SwiftData store is read and imported (`data/legacy/swiftDataStore.ts`). The old files are only read, never changed.

## Interface requirements
- Controls large enough for gym use; common actions never more than a tap or two away.
- No confirmations during normal logging; only for finishing, and for destructive actions.
- Light and dark appearance follow the system setting.
- Five tabs: Today, Workout, Program, History, Settings. Settings shows the version and build number.

## Success criteria
The app succeeds if the user can:
- See at once whether today is a workout or rest day.
- Log a full workout quickly from a phone.
- Tell previous values from today's entries, without old data being silently re-saved.
- Reach an exercise's note when needed without it cluttering the list.
- Get a correct daily reminder when enabled.
- See total volume during the session and afterwards.
- Export the program and history to a spreadsheet.
- Fix a missed day from the Today screen without re-doing the calendar by hand.
- Re-import an updated program without losing previous weights for exercises that carried over.

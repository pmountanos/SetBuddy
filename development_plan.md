# Development Plan

Where the project has been, where it is, and what is next.

## Status (October 2026)
Set Buddy is a React Native app (Expo) for iPhone and Android, in `mobile/`. Everything in `requirements.md` is implemented. It is in daily use on an iPhone. On Android it has been exercised end to end on the emulator, and a release-signed APK builds, but no physical Android phone has run it yet.

## Next
In rough priority order:
1. **Run it on a physical Android phone**, including the upgrade from the earlier Kotlin app and reminder delivery.
2. **Move to stable Expo SDK 58** when it is released, then remove `mobile/.npmrc`.
3. **Check the iPhone flows that have only been spot-checked:** spreadsheet import through the Files picker, both exports, and reminder delivery at the chosen time.
4. **Smaller Android builds.** The APK carries code for four processor types and is about 100 MB; building for phones only would cut it to roughly a quarter.
5. **Automated UI tests** for the logging flow, which is where the bugs found so far have been.
6. **Remove the first-launch import of the native apps' data** once nobody is upgrading from those builds.

## Ideas, not commitments
Multiple programs; richer history (trends, personal records); pounds as well as kilograms; cloud backup or sync; a watch companion; widgets; importable history; tablet layouts.

## How to work on it
- Changes go through pull requests against `main`.
- Before opening one, run the four checks in `architecture.md` → **Tests and checks**.
- A behaviour change should come with a test. The data layer, import, export and reminder planning are all testable in Node; see the existing tests for the pattern.
- A schema change needs a migration (see `architecture.md` → **Constraints that will bite**).
- Keep the Apple team ID, the keystore and anything else personal out of tracked files.

## History

### March–September 2026: native iPhone app
The first version was a SwiftUI app using SwiftData, built in phases: project setup; domain model and persistence; the Today screen and schedule resolution; workout logging; reference values from the previous session; volume tracking; exercise notes and `.xlsx` import; daily notifications; History; the Program tab and Settings; then testing and stabilisation. Later additions were in-app program editing, spreadsheet export, name-based carry-over of exercise history across imports, and "Change today's plan" for realigning the schedule after a missed day.

### September 2026: Android, and cardio
An Android app was added on 2026-09-12 and reached feature parity on 2026-09-16: Jetpack Compose for the interface, with the scheduling, volume and carry-over logic and the persistence schema in a Kotlin Multiplatform module backed by SQLDelight.

On 2026-09-28 the iPhone app gained cardio exercises (minutes and max heart rate), followed by cardio sections in spreadsheet import. Real use over the next days produced several fixes: a crash importing a workbook that repeated an exercise name; the keyboard closing when moving from weight to reps; cardio defaulting to four sets; the schedule cascade duplicating a workout and delaying the whole cycle when a workout was pulled forward; workouts listing in name order rather than rotation order; and a launch crash from a missing storage migration default. On 2026-10-04, finished workouts became reopenable, and Android was brought back in line with all of the above.

### October 2026: one React Native app
On 2026-10-04 the decision was made to replace both native apps with a single Expo app, on the condition that existing workout history was kept.

- **Data first.** The riskiest part was done first: reading the iPhone app's SwiftData store. It was developed against a copy of a real device store and verified lossless (every row, and identical volume per session). The database schema was made identical to the Android app's, so on Android the old file is simply adopted.
- **Port.** The domain logic and repositories were ported from the Kotlin module with their tests, then spreadsheet import and export.
- **Screens.** The five tabs were built on Expo Router and exercised on the Android emulator, installed over the Kotlin app. That testing found and fixed three bugs: reps lost when pressing Done (values are now stored as typed), the bottom bar hidden behind the Android keyboard, and cleared sets being saved on Finish.
- **Reminders** were added, then iPhone and Android release builds with proper signing.
- **On a phone.** The app was installed over the native app on an iPhone on 2026-10-05 and imported its history intact. The native projects were retired the same day.

Two constraints surfaced along the way and shaped the setup: Xcode 27 requires Expo SDK 58, then still a pre-release; and Expo's native build scripts fail when the repository path contains a space.

### Deliberate differences from the native apps
- A set entered and then cleared back to nothing is dropped on Finish.
- The importer reads the **Type** column that the program export writes, so an exported program with cardio imports back unchanged.
- Values are stored as they are typed rather than when a field loses focus.
- An empty, never-entered set that is merely tapped is not marked as entered.

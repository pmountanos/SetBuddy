# Context

## What Set Buddy is
Set Buddy is a phone app for logging strength workouts quickly while you are in the gym. You follow **one** training program, the app tells you each day whether it is a workout or a rest day, and you log **weight and reps** for each set. Your most recent numbers for each exercise are shown as a reference so you can see what to beat. **Total volume** (weight × reps) is the progress measure.

It is deliberately narrow: no social features, no coaching, no deep analytics. It is built for repeated daily use on a phone held in one hand between sets.

It runs on iPhone and Android from a single React Native codebase in `mobile/`.

## Who it is for
One lifter who trains on a repeating schedule, wants minimal taps, and cares about volume more than charts.

## How it behaves
- **Today** shows the day's status: a workout (with **Start**), a workout in progress (**Continue**), a finished workout (**Reopen**, in case Finish was tapped by mistake), a rest day, or no program yet. **Change today's plan** forces today onto a different workout or rest — for example after missing a day — and shifts the following days so the rotation stays in order.
- **Workout** is the logging screen. Each set has two large numeric fields: weight (kg) and reps. The last logged values for that exercise appear in **orange** as a reference; once you enter or confirm a set it turns to a **high-contrast** style. A bar at the bottom shows session volume, a **Done** button to dismiss the number pad, and **Finish**.
- **Only what you enter is saved.** Finishing a workout drops any set you never touched, and any set you entered and then cleared.
- **Cardio** exercises log **minutes** and **max heart rate** instead of weight and reps, with the same reference and entered styling. They do not count toward volume. A cardio day is simply a workout made of cardio exercises.
- **Program** shows the program's name, the upcoming schedule (7, 14 or 21 days) with a menu on each day, and every workout with its exercises. Workouts are fully editable in the app: rename, add, remove and reorder exercises, set count (1–20), strength or cardio, and whether reps are per side (which doubles volume).
- **History** lists completed sessions with their volume; each opens to show every set, with an editable workout note.
- **Settings** holds the daily reminder (on/off and time), the schedule length, spreadsheet import, and export of the program and of the full history.
- **Exercise notes** stay out of the way: tap an exercise's name to read or edit its note.
- **Daily reminders** are local notifications, one per day, saying whether it is a workout or rest day.

## Spreadsheets
- **Import** reads an `.xlsx` workbook in which each worksheet is one day of the rotation, in tab order. After picking a file you choose which day comes next and which calendar day it falls on. Importing replaces the program and schedule; completed sessions stay in History and a workout in progress is cleared.
- When a program already exists, the new workbook's exercises are **matched by name** against it so reference values carry over: exact matches silently, close matches (at least 75% similar) offered for confirmation.
- **Export** produces `.xlsx` files (falling back to `.csv` if a workbook cannot be built) through the system share sheet. The program export can be imported back unchanged.

## Decisions worth knowing
| Topic | Decision |
|---|---|
| Programs | Exactly one active program |
| Schedule | One stored row per calendar day, kept about 28 weeks ahead |
| Reference values | Most recent *completed* set for that exercise, from any workout |
| What is saved | Only sets the user entered; values are stored as they are typed |
| Volume | Weight × reps, doubled for per-side exercises; cardio excluded |
| Units | Kilograms only |
| Default sets | 4 for strength, 1 for cardio; editable 1–20 |
| Storage | Local SQLite on the device; no account, no sync, works offline |
| Reminders | One local notification per day for the next 14 days, re-planned whenever the schedule changes |

## Not in scope
Multiple programs, cloud sync, wearables, social features, coaching, target reps, exercise media, pounds, and tablet-specific layouts.

## Where things stand
The app is in daily use on an iPhone. It replaced two earlier native apps (SwiftUI on iOS, Kotlin on Android) on 2026-10-05 and imported their on-device data on first launch; that import code is still present for anyone upgrading from those builds. The Android build has been exercised on the emulator but not yet on a physical phone. See `development_plan.md` for history and what is next, `requirements.md` for the detailed requirements, and `architecture.md` for how the code is organised.

## Licence
Source-available under the PolyForm Noncommercial License 1.0.0: free to use, modify and share for noncommercial purposes. See `LICENSE.md`.

# Set Buddy

A phone app for logging strength workouts fast, while you are in the gym.

You follow one training program. Each day the app tells you whether it is a workout or a rest day. When you train, you log weight and reps for each set, with your last numbers for that exercise shown as a reference. Progress is measured in total volume (weight × reps).

It runs on iPhone and Android from one React Native codebase. Everything is stored on the device: no account, no sync, no network.

## What it does
- **Today** — workout or rest day at a glance, with Start, Continue or Reopen.
- **Fast set entry** — large numeric fields for weight (kg) and reps. Previous values appear in orange as a reference and switch to a high-contrast style once you enter them. Only sets you actually enter are saved.
- **Cardio** — exercises can log minutes and max heart rate instead of weight and reps.
- **Program editing** — workouts, exercises, set counts, per-side exercises and notes, all editable in the app.
- **Schedule that survives real life** — missed a day? Change today's plan and the rest of the rotation shifts to stay in order.
- **Spreadsheet import** — bring in a program from an `.xlsx` workbook, one worksheet per day of your rotation.
- **Export** — your program and your full history as spreadsheets.
- **History** — every completed session with its volume and every set.
- **Daily reminder** — an optional notification saying what today holds.

## Status
In daily use on an iPhone. The Android build has been tested on the emulator but not yet on a physical phone. See [development_plan.md](development_plan.md) for what is next.

## Building it yourself
You will need **Node 24**, and for iPhone builds a Mac with **Xcode 27** and **CocoaPods**; for Android builds, **Android Studio** (for its SDK and JDK).

```sh
cd mobile
npm install
npx jest            # unit tests
npx tsc --noEmit    # typecheck
npx expo lint       # lint
```

Run it in the iOS simulator:

```sh
npx expo run:ios --configuration Release --device "iPhone 17" --no-bundler
```

Two things to know before your first native build:

- **Clone into a path with no spaces.** Expo's native build scripts fail otherwise.
- **Building for a real iPhone needs your own Apple Developer team ID.** Copy `signing.local.env.example` to `signing.local.env` and fill it in. That file is ignored by git. Then run `./scripts/archive_mobile_ios.sh`.

For a release-signed Android build, see the comments at the top of [scripts/build_mobile_android.sh](scripts/build_mobile_android.sh).

The project is currently on a pre-release of Expo SDK 58, because Xcode 27 requires it.

## Importing a program from a spreadsheet
Each worksheet is one day of your rotation, in tab order.

- Column **A** is the exercise name, one exercise per row.
- Optional row-1 headers **Notes** and **Per side** label those columns. Without headers, column B is the note and column C marks per-side exercises (`x`, `yes` or `✓`).
- A worksheet with no exercises, or with "Rest" in its name, is a rest day.
- A row reading **Minutes** then **Peak HR** starts a cardio section: every exercise below it on that sheet is cardio.

After choosing the file you pick which day of the workbook comes next and which calendar day it falls on. Two real examples are in [mobile/src/xlsx/\_\_tests\_\_/fixtures/](mobile/src/xlsx/__tests__/fixtures/).

## How the code is organised
All application code is in `mobile/src/`: pure logic in `domain/`, SQLite storage in `data/`, screens in `app/`. [architecture.md](architecture.md) explains the layers and the reasoning; [requirements.md](requirements.md) lists what the app must do; [context.md](context.md) is a short product overview.

## Contributing
Bug reports and pull requests are welcome. Please run the tests, typecheck and lint before opening a pull request, and include a test with any change in behaviour. By contributing you agree that your contribution is licensed under the same terms as the project.

## Licence
Set Buddy is **source-available**, not open source. It is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE.md):

- You **may** use it, change it and share it for any noncommercial purpose, including personal use.
- You **may not** sell it or use it commercially, including as part of a paid app.

Required Notice: Copyright (c) 2026 Pete Mountanos (https://github.com/pmountanos)

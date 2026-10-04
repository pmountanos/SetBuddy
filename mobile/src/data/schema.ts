import type { Db } from './db';

/**
 * Same tables, columns and version numbers as the Kotlin app's SQLDelight schema (`SetBuddy.sq` + `1.sqm`),
 * so an existing Android `setbuddy.db` is adopted as-is and only ever needs the same forward migrations.
 */
export const SCHEMA_VERSION = 2;

const CREATE_V2 = `
CREATE TABLE Program (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    createdAtRowOrder INTEGER NOT NULL
);

CREATE TABLE Workout (
    id TEXT NOT NULL PRIMARY KEY,
    programId TEXT NOT NULL,
    name TEXT NOT NULL,
    -- Display/picker order: first-encountered position in the imported spreadsheet's cycle, or append order for
    -- workouts added in-app. Ties fall back to the Push/Pull/Legs naming heuristic.
    sortOrder INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (programId) REFERENCES Program(id) ON DELETE CASCADE
);
CREATE INDEX Workout_programId ON Workout(programId);

CREATE TABLE ScheduleEntry (
    id TEXT NOT NULL PRIMARY KEY,
    programId TEXT NOT NULL,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL,
    day INTEGER NOT NULL,
    isRestDay INTEGER NOT NULL,
    workoutId TEXT,
    FOREIGN KEY (programId) REFERENCES Program(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX ScheduleEntry_program_date ON ScheduleEntry(programId, year, month, day);

CREATE TABLE Exercise (
    id TEXT NOT NULL PRIMARY KEY,
    workoutId TEXT NOT NULL,
    name TEXT NOT NULL,
    sortOrder INTEGER NOT NULL,
    setCount INTEGER NOT NULL,
    note TEXT,
    repsArePerSide INTEGER NOT NULL DEFAULT 0,
    -- 'strength' (weight/reps) or 'cardio' (minutes/max heart rate).
    kind TEXT NOT NULL DEFAULT 'strength',
    FOREIGN KEY (workoutId) REFERENCES Workout(id) ON DELETE CASCADE
);
CREATE INDEX Exercise_workoutId ON Exercise(workoutId);

-- Not FK-cascaded to Workout: a session must survive its template being deleted/replaced (program re-import),
-- which is why workoutTitleSnapshot exists to keep History readable afterward.
CREATE TABLE WorkoutSession (
    id TEXT NOT NULL PRIMARY KEY,
    workoutTemplateId TEXT NOT NULL,
    scheduleYear INTEGER NOT NULL,
    scheduleMonth INTEGER NOT NULL,
    scheduleDay INTEGER NOT NULL,
    isComplete INTEGER NOT NULL DEFAULT 0,
    createdAt INTEGER NOT NULL,
    completedAt INTEGER,
    workoutTitleSnapshot TEXT,
    sessionNote TEXT
);
CREATE INDEX WorkoutSession_template_date ON WorkoutSession(workoutTemplateId, scheduleYear, scheduleMonth, scheduleDay);

CREATE TABLE LoggedSet (
    id TEXT NOT NULL PRIMARY KEY,
    sessionId TEXT NOT NULL,
    exerciseId TEXT NOT NULL,
    setIndex INTEGER NOT NULL,
    weight REAL NOT NULL DEFAULT 0,
    reps INTEGER NOT NULL DEFAULT 0,
    seededFromCarryover INTEGER NOT NULL DEFAULT 0,
    userEditedValues INTEGER NOT NULL DEFAULT 0,
    repsArePerSide INTEGER NOT NULL DEFAULT 0,
    -- Cardio-exercise values (unused/zero for strength sets).
    cardioMinutes REAL NOT NULL DEFAULT 0,
    maxHeartRate INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (sessionId) REFERENCES WorkoutSession(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX LoggedSet_session_exercise_index ON LoggedSet(sessionId, exerciseId, setIndex);
`;

/** Forward migrations, keyed by the version they upgrade *from*. */
const MIGRATIONS: Record<number, string> = {
  1: `
ALTER TABLE Workout ADD COLUMN sortOrder INTEGER NOT NULL DEFAULT 0;
ALTER TABLE Exercise ADD COLUMN kind TEXT NOT NULL DEFAULT 'strength';
ALTER TABLE LoggedSet ADD COLUMN cardioMinutes REAL NOT NULL DEFAULT 0;
ALTER TABLE LoggedSet ADD COLUMN maxHeartRate INTEGER NOT NULL DEFAULT 0;
`,
};

export function schemaVersion(db: Db): number {
  return db.first<{ user_version: number }>('PRAGMA user_version')?.user_version ?? 0;
}

/**
 * Brings `db` to {@link SCHEMA_VERSION}: creates the tables in an empty database, or applies forward migrations
 * to an existing one (including a `setbuddy.db` adopted from the Kotlin Android app). Call once at startup.
 */
export function prepareDatabase(db: Db): void {
  db.exec('PRAGMA foreign_keys = ON');
  let version = schemaVersion(db);
  if (version > SCHEMA_VERSION) {
    throw new Error(`Database is version ${version}; this build only understands up to ${SCHEMA_VERSION}.`);
  }
  if (version === SCHEMA_VERSION) return;
  db.transaction(() => {
    if (version === 0) {
      db.exec(CREATE_V2);
      version = SCHEMA_VERSION;
    }
    while (version < SCHEMA_VERSION) {
      db.exec(MIGRATIONS[version]);
      version += 1;
    }
    db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
  });
}

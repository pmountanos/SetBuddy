import { prepareDatabase, SCHEMA_VERSION, schemaVersion } from '../schema';
import { openTestDb } from './testDb';

/** The Kotlin Android app's schema as first released (versionCode 2), before cardio / workout sortOrder. */
const ANDROID_V1 = `
CREATE TABLE Program (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, createdAtRowOrder INTEGER NOT NULL);
CREATE TABLE Workout (id TEXT NOT NULL PRIMARY KEY, programId TEXT NOT NULL, name TEXT NOT NULL,
  FOREIGN KEY (programId) REFERENCES Program(id) ON DELETE CASCADE);
CREATE TABLE ScheduleEntry (id TEXT NOT NULL PRIMARY KEY, programId TEXT NOT NULL, year INTEGER NOT NULL,
  month INTEGER NOT NULL, day INTEGER NOT NULL, isRestDay INTEGER NOT NULL, workoutId TEXT,
  FOREIGN KEY (programId) REFERENCES Program(id) ON DELETE CASCADE);
CREATE UNIQUE INDEX ScheduleEntry_program_date ON ScheduleEntry(programId, year, month, day);
CREATE TABLE Exercise (id TEXT NOT NULL PRIMARY KEY, workoutId TEXT NOT NULL, name TEXT NOT NULL,
  sortOrder INTEGER NOT NULL, setCount INTEGER NOT NULL, note TEXT, repsArePerSide INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (workoutId) REFERENCES Workout(id) ON DELETE CASCADE);
CREATE TABLE WorkoutSession (id TEXT NOT NULL PRIMARY KEY, workoutTemplateId TEXT NOT NULL,
  scheduleYear INTEGER NOT NULL, scheduleMonth INTEGER NOT NULL, scheduleDay INTEGER NOT NULL,
  isComplete INTEGER NOT NULL DEFAULT 0, createdAt INTEGER NOT NULL, completedAt INTEGER,
  workoutTitleSnapshot TEXT, sessionNote TEXT);
CREATE TABLE LoggedSet (id TEXT NOT NULL PRIMARY KEY, sessionId TEXT NOT NULL, exerciseId TEXT NOT NULL,
  setIndex INTEGER NOT NULL, weight REAL NOT NULL DEFAULT 0, reps INTEGER NOT NULL DEFAULT 0,
  seededFromCarryover INTEGER NOT NULL DEFAULT 0, userEditedValues INTEGER NOT NULL DEFAULT 0,
  repsArePerSide INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (sessionId) REFERENCES WorkoutSession(id) ON DELETE CASCADE);
CREATE UNIQUE INDEX LoggedSet_session_exercise_index ON LoggedSet(sessionId, exerciseId, setIndex);
PRAGMA user_version = 1;
`;

const columns = (db: ReturnType<typeof openTestDb>, table: string) =>
  db.all<{ name: string }>(`SELECT name FROM pragma_table_info('${table}')`).map((c) => c.name);

describe('prepareDatabase', () => {
  it('creates the current schema in an empty database', () => {
    const db = openTestDb();
    prepareDatabase(db);
    expect(schemaVersion(db)).toBe(SCHEMA_VERSION);
    expect(columns(db, 'Exercise')).toContain('kind');
    expect(columns(db, 'LoggedSet')).toEqual(expect.arrayContaining(['cardioMinutes', 'maxHeartRate']));
    prepareDatabase(db); // idempotent
  });

  it('upgrades a database adopted from the first Android release, keeping its rows', () => {
    const db = openTestDb();
    db.exec(ANDROID_V1);
    db.exec(`
      INSERT INTO Program VALUES ('p', 'Old program', 1);
      INSERT INTO Workout VALUES ('w', 'p', 'Push 1');
      INSERT INTO Exercise VALUES ('e', 'w', 'Bench Press', 0, 4, NULL, 0);
      INSERT INTO WorkoutSession VALUES ('s', 'w', 2026, 9, 16, 1, 1, 2, 'Push 1', NULL);
      INSERT INTO LoggedSet VALUES ('l', 's', 'e', 0, 100.0, 5, 0, 1, 0);
    `);

    prepareDatabase(db);

    expect(schemaVersion(db)).toBe(SCHEMA_VERSION);
    expect(db.first('SELECT name, sortOrder FROM Workout')).toEqual({ name: 'Push 1', sortOrder: 0 });
    expect(db.first('SELECT name, kind FROM Exercise')).toEqual({ name: 'Bench Press', kind: 'strength' });
    expect(db.first('SELECT weight, reps, cardioMinutes, maxHeartRate FROM LoggedSet')).toEqual({
      weight: 100,
      reps: 5,
      cardioMinutes: 0,
      maxHeartRate: 0,
    });
  });

  it('leaves a current Android database alone', () => {
    const db = openTestDb();
    prepareDatabase(db);
    db.exec("INSERT INTO Program VALUES ('p', 'Kept', 1)");
    prepareDatabase(db);
    expect(db.first('SELECT name FROM Program')).toEqual({ name: 'Kept' });
  });

  it('refuses a database from a newer build rather than guessing', () => {
    const db = openTestDb();
    db.exec('PRAGMA user_version = 99');
    expect(() => prepareDatabase(db)).toThrow(/version 99/);
  });
});

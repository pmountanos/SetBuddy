import { existsSync } from 'node:fs';

import type { Db } from '../db';
import {
  epochMillisFromCoreDataDate,
  importSwiftDataStore,
  isSetBuddySwiftDataStore,
  uuidFromHex,
} from '../legacy/swiftDataStore';
import { prepareDatabase } from '../schema';
import { newId, openTestDb } from './testDb';

/** Table definitions exactly as SwiftData wrote them on-device (build 14). */
const SWIFTDATA_SCHEMA = `
CREATE TABLE ZPERSISTEDPROGRAM ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZNAME VARCHAR );
CREATE TABLE ZPERSISTEDWORKOUT ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZPROGRAM INTEGER, ZNAME VARCHAR, ZID BLOB , ZSORTORDER INTEGER);
CREATE TABLE ZPERSISTEDSCHEDULEENTRY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZDAY INTEGER, ZISRESTDAY INTEGER, ZMONTH INTEGER, ZYEAR INTEGER, ZPROGRAM INTEGER, ZWORKOUTID BLOB );
CREATE TABLE ZPERSISTEDEXERCISE ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZREPSAREPERSIDE INTEGER, ZSETCOUNT INTEGER, ZSORTORDER INTEGER, ZWORKOUT INTEGER, ZKIND VARCHAR, ZNAME VARCHAR, ZNOTE VARCHAR, ZID BLOB );
CREATE TABLE ZPERSISTEDWORKOUTSESSION ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZISCOMPLETE INTEGER, ZSCHEDULEDAY INTEGER, ZSCHEDULEMONTH INTEGER, ZSCHEDULEYEAR INTEGER, ZCOMPLETEDAT TIMESTAMP, ZCREATEDAT TIMESTAMP, ZSESSIONNOTE VARCHAR, ZWORKOUTTITLESNAPSHOT VARCHAR, ZID BLOB, ZWORKOUTTEMPLATEID BLOB );
CREATE TABLE ZPERSISTEDLOGGEDSET ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZMAXHEARTRATE INTEGER, ZREPS INTEGER, ZREPSAREPERSIDE INTEGER, ZSEEDEDFROMCARRYOVER INTEGER, ZSETINDEX INTEGER, ZUSEREDITEDVALUES INTEGER, ZSESSION INTEGER, ZCARDIOMINUTES FLOAT, ZWEIGHT FLOAT, ZEXERCISEID BLOB );
`;

const PUSH = '294b2676-3877-4cde-a44a-9f6e5a42aa37';
const CARDIO_DAY = 'dd04192e-327b-4861-9590-9f59d1a71850';
const BENCH = 'b9973b31-055c-48b8-88a9-8e6a11b8e74d';
const HIP = '8772724c-7c52-4a9f-8e8b-679e81fd7bb9';
const TREADMILL = '11b0cf99-a613-4d5c-80eb-9034164b8387';
const SESSION = '51b71d0f-589a-46ba-8c01-68b8539b5da9';
const blob = (uuid: string) => `x'${uuid.replace(/-/g, '')}'`;

function syntheticStore(): Db {
  const store = openTestDb();
  store.exec(SWIFTDATA_SCHEMA);
  store.exec(`
    INSERT INTO ZPERSISTEDPROGRAM VALUES (7, 1, 1, 'Set Buddy-4');
    INSERT INTO ZPERSISTEDWORKOUT VALUES (51, 2, 1, 7, 'Push 2', ${blob(PUSH)}, 5);
    INSERT INTO ZPERSISTEDWORKOUT VALUES (54, 2, 1, 7, 'Cardio 1', ${blob(CARDIO_DAY)}, 1);
    -- An exercise whose columns predate the cardio/sortOrder fields (NULL kind), and a copy-paste duplicate
    -- that the native importer gave the same id.
    INSERT INTO ZPERSISTEDEXERCISE VALUES (280, 3, 1, 0, 4, 0, 51, NULL, 'Bench Press', 'Pause at the bottom', ${blob(BENCH)});
    INSERT INTO ZPERSISTEDEXERCISE VALUES (281, 3, 1, 1, 4, 1, 51, 'strength', 'Hip adduction', NULL, ${blob(HIP)});
    INSERT INTO ZPERSISTEDEXERCISE VALUES (282, 3, 1, 1, 4, 2, 51, 'strength', 'Hip adduction', NULL, ${blob(HIP)});
    INSERT INTO ZPERSISTEDEXERCISE VALUES (283, 3, 1, 0, 1, 0, 54, 'cardio', 'Cardio', NULL, ${blob(TREADMILL)});
    INSERT INTO ZPERSISTEDSCHEDULEENTRY VALUES (1, 4, 1, 4, 0, 10, 2026, 7, ${blob(PUSH)});
    INSERT INTO ZPERSISTEDSCHEDULEENTRY VALUES (2, 4, 1, 5, 1, 10, 2026, 7, NULL);
    -- A second row for a day that already has one: the later row wins.
    INSERT INTO ZPERSISTEDSCHEDULEENTRY VALUES (3, 4, 1, 5, 0, 10, 2026, 7, ${blob(CARDIO_DAY)});
    INSERT INTO ZPERSISTEDWORKOUTSESSION VALUES (5, 5, 1, 1, 4, 10, 2026, 812818689.493096, 812798556.82891, 'Felt strong', 'Push 2', ${blob(SESSION)}, ${blob(PUSH)});
    INSERT INTO ZPERSISTEDLOGGEDSET VALUES (142, 6, 1, 0, 15, 0, 0, 0, 1, 5, 0.0, 45.0, ${blob(BENCH)});
    INSERT INTO ZPERSISTEDLOGGEDSET VALUES (143, 6, 1, 0, 10, 1, 0, 0, 1, 5, 0.0, 25.0, ${blob(HIP)});
    INSERT INTO ZPERSISTEDLOGGEDSET VALUES (146, 6, 1, 130, 0, 0, 0, 0, 1, 5, 30.0, 0.0, ${blob(TREADMILL)});
    -- Same slot as row 142 but never entered: must lose to the entered row.
    INSERT INTO ZPERSISTEDLOGGEDSET VALUES (140, 6, 1, 0, 0, 0, 0, 0, 0, 5, 0.0, 0.0, ${blob(BENCH)});
    -- A set whose session no longer exists.
    INSERT INTO ZPERSISTEDLOGGEDSET VALUES (147, 6, 1, 0, 5, 0, 0, 0, 1, 999, 0.0, 10.0, ${blob(BENCH)});
  `);
  return store;
}

function preparedTarget() {
  const target = openTestDb();
  prepareDatabase(target);
  return target;
}

describe('SwiftData value decoding', () => {
  it('formats a UUID blob the way the Kotlin app stored ids', () => {
    expect(uuidFromHex('294b267638774cdea44a9f6e5a42aa37')).toBe(PUSH);
    expect(() => uuidFromHex('nope')).toThrow();
  });

  it('converts Core Data timestamps (seconds since 2001) to epoch milliseconds', () => {
    expect(epochMillisFromCoreDataDate(0)).toBe(Date.UTC(2001, 0, 1));
    expect(new Date(epochMillisFromCoreDataDate(812818689.493096)).toISOString()).toBe('2026-10-04T14:58:09.493Z');
  });
});

describe('importSwiftDataStore', () => {
  it('recognises the store by its model tables', () => {
    expect(isSetBuddySwiftDataStore(syntheticStore())).toBe(true);
    expect(isSetBuddySwiftDataStore(openTestDb())).toBe(false);
  });

  it('carries over the program, templates, schedule and history', () => {
    const target = preparedTarget();
    const summary = importSwiftDataStore(syntheticStore(), target, newId);

    expect(summary).toMatchObject({ programs: 1, workouts: 2, exercises: 4, scheduleEntries: 2, sessions: 1, loggedSets: 3 });
    expect(summary.skipped).toEqual({ scheduleEntries: 1, loggedSets: 1, orphans: 1 });

    const program = target.first<{ id: string; name: string }>('SELECT id, name FROM Program')!;
    expect(program.name).toBe('Set Buddy-4');
    expect(target.all('SELECT id, name, sortOrder FROM Workout ORDER BY sortOrder')).toEqual([
      { id: CARDIO_DAY, name: 'Cardio 1', sortOrder: 1 },
      { id: PUSH, name: 'Push 2', sortOrder: 5 },
    ]);

    expect(target.first('SELECT name, note, setCount, kind FROM Exercise WHERE id = ?', [BENCH])).toEqual({
      name: 'Bench Press',
      note: 'Pause at the bottom',
      setCount: 4,
      kind: 'strength',
    });
    expect(target.first('SELECT kind, setCount FROM Exercise WHERE id = ?', [TREADMILL])).toEqual({ kind: 'cardio', setCount: 1 });

    expect(target.all('SELECT day, isRestDay, workoutId FROM ScheduleEntry ORDER BY day')).toEqual([
      { day: 4, isRestDay: 0, workoutId: PUSH },
      { day: 5, isRestDay: 0, workoutId: CARDIO_DAY },
    ]);

    expect(target.first('SELECT * FROM WorkoutSession')).toEqual({
      id: SESSION,
      workoutTemplateId: PUSH,
      scheduleYear: 2026,
      scheduleMonth: 10,
      scheduleDay: 4,
      isComplete: 1,
      createdAt: Date.parse('2026-10-04T09:22:36.829Z'),
      completedAt: Date.parse('2026-10-04T14:58:09.493Z'),
      workoutTitleSnapshot: 'Push 2',
      sessionNote: 'Felt strong',
    });
  });

  it('keeps the entered values when a set slot appears twice', () => {
    const target = preparedTarget();
    importSwiftDataStore(syntheticStore(), target, newId);
    expect(
      target.all('SELECT exerciseId, weight, reps, repsArePerSide, cardioMinutes, maxHeartRate, userEditedValues FROM LoggedSet ORDER BY weight DESC'),
    ).toEqual([
      { exerciseId: BENCH, weight: 45, reps: 15, repsArePerSide: 0, cardioMinutes: 0, maxHeartRate: 0, userEditedValues: 1 },
      { exerciseId: HIP, weight: 25, reps: 10, repsArePerSide: 1, cardioMinutes: 0, maxHeartRate: 0, userEditedValues: 1 },
      { exerciseId: TREADMILL, weight: 0, reps: 0, repsArePerSide: 0, cardioMinutes: 30, maxHeartRate: 130, userEditedValues: 1 },
    ]);
  });

  it('gives a duplicated exercise id to the first exercise only', () => {
    const target = preparedTarget();
    const summary = importSwiftDataStore(syntheticStore(), target, newId);
    expect(summary.reassignedExerciseIds).toBe(1);
    const hips = target.all<{ id: string; sortOrder: number }>("SELECT id, sortOrder FROM Exercise WHERE name = 'Hip adduction' ORDER BY sortOrder");
    expect(hips).toHaveLength(2);
    expect(hips[0].id).toBe(HIP);
    expect(hips[1].id).not.toBe(HIP);
  });

  it('writes nothing if the import fails part-way', () => {
    const store = syntheticStore();
    store.exec("UPDATE ZPERSISTEDWORKOUTSESSION SET ZID = x'00'");
    const target = preparedTarget();
    expect(() => importSwiftDataStore(store, target, newId)).toThrow(/Not a UUID/);
    expect(target.first<{ n: number }>('SELECT count(*) AS n FROM Program')!.n).toBe(0);
  });
});

/**
 * Runs against a real `default.store` copied off a device when one is supplied:
 *   SETBUDDY_REAL_STORE=/path/to/default.store npx jest swiftDataStore
 * Asserts the import is lossless by re-deriving the totals from the source store itself.
 */
const realStorePath = process.env.SETBUDDY_REAL_STORE;
(realStorePath && existsSync(realStorePath) ? describe : describe.skip)('a real on-device store', () => {
  it('imports every row and preserves total volume per session', () => {
    const store = openTestDb(realStorePath!, { readonly: true });
    const target = preparedTarget();
    const summary = importSwiftDataStore(store, target, newId);
    const count = (db: Db, table: string) => db.first<{ n: number }>(`SELECT count(*) AS n FROM ${table}`)!.n;

    expect(summary.programs).toBe(count(store, 'ZPERSISTEDPROGRAM'));
    expect(summary.workouts).toBe(count(store, 'ZPERSISTEDWORKOUT'));
    expect(summary.exercises).toBe(count(store, 'ZPERSISTEDEXERCISE'));
    expect(summary.sessions).toBe(count(store, 'ZPERSISTEDWORKOUTSESSION'));
    expect(summary.loggedSets + summary.skipped.loggedSets + summary.skipped.orphans).toBe(count(store, 'ZPERSISTEDLOGGEDSET'));
    expect(summary.scheduleEntries + summary.skipped.scheduleEntries).toBe(count(store, 'ZPERSISTEDSCHEDULEENTRY'));

    const volume = 'sum(CASE WHEN perSide THEN 2 ELSE 1 END * weight * reps)';
    const before = store.all(
      `SELECT lower(hex(s.ZID)) AS id, ${volume} AS volume, sum(minutes) AS minutes, count(*) AS sets FROM (
         SELECT ZSESSION, ZREPSAREPERSIDE AS perSide, ZWEIGHT AS weight, ZREPS AS reps, ZCARDIOMINUTES AS minutes
         FROM ZPERSISTEDLOGGEDSET WHERE ZUSEREDITEDVALUES = 1
       ) l JOIN ZPERSISTEDWORKOUTSESSION s ON s.Z_PK = l.ZSESSION GROUP BY s.Z_PK ORDER BY id`,
    );
    const after = target.all(
      `SELECT replace(sessionId, '-', '') AS id, ${volume} AS volume, sum(minutes) AS minutes, count(*) AS sets FROM (
         SELECT sessionId, repsArePerSide AS perSide, weight, reps, cardioMinutes AS minutes
         FROM LoggedSet WHERE userEditedValues = 1
       ) GROUP BY sessionId ORDER BY id`,
    );
    expect(after).toEqual(before);
    expect(after.length).toBeGreaterThan(0);

    // Every imported set and schedule day points at something that exists.
    expect(target.first<{ n: number }>('SELECT count(*) AS n FROM LoggedSet WHERE sessionId NOT IN (SELECT id FROM WorkoutSession)')!.n).toBe(0);
    expect(
      target.first<{ n: number }>('SELECT count(*) AS n FROM ScheduleEntry WHERE isRestDay = 0 AND workoutId NOT IN (SELECT id FROM Workout)')!.n,
    ).toBe(0);
    console.log('Real store import summary:', JSON.stringify(summary));
  });
});

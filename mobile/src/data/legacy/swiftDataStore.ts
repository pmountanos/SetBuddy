import type { Db } from '../db';

/**
 * One-time import of the native iOS app's SwiftData store (`Library/Application Support/default.store`) into the
 * React Native app's database, so the upgrade keeps the program, schedule and all workout history.
 *
 * SwiftData persists through Core Data's SQLite layout: one `ZPERSISTED…` table per model, integer `Z_PK` row
 * ids, relationships as integer columns pointing at the parent's `Z_PK`, `UUID`s as 16-byte blobs, and `Date`s
 * as seconds since 2001-01-01 UTC. Column names below were read from a real store written by build 14.
 */

/** Seconds between the Unix epoch and Core Data's reference date (2001-01-01T00:00:00Z). */
const CORE_DATA_EPOCH_OFFSET_SECONDS = 978_307_200;

export interface SwiftDataImportSummary {
  programs: number;
  workouts: number;
  exercises: number;
  scheduleEntries: number;
  sessions: number;
  loggedSets: number;
  /** Source rows that could not be carried over as-is (e.g. a second entry for the same calendar day). */
  skipped: { scheduleEntries: number; loggedSets: number; orphans: number };
  /** Exercises that shared an id with an earlier one and were given a fresh id. */
  reassignedExerciseIds: number;
}

/** `lower(hex(blob))` of a 16-byte UUID → canonical `8-4-4-4-12` form (the form the Kotlin app stored). */
export function uuidFromHex(hex: string): string {
  if (!/^[0-9a-f]{32}$/.test(hex)) throw new Error(`Not a UUID blob: ${hex}`);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function epochMillisFromCoreDataDate(seconds: number): number {
  return Math.round((seconds + CORE_DATA_EPOCH_OFFSET_SECONDS) * 1000);
}

/** True when `source` looks like the Set Buddy SwiftData store (all six model tables present). */
export function isSetBuddySwiftDataStore(source: Db): boolean {
  const found = source.all<{ name: string }>(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'ZPERSISTED%'",
  );
  const names = new Set(found.map((row) => row.name));
  return ['PROGRAM', 'WORKOUT', 'SCHEDULEENTRY', 'EXERCISE', 'WORKOUTSESSION', 'LOGGEDSET'].every((model) =>
    names.has(`ZPERSISTED${model}`),
  );
}

/**
 * Copies everything from `source` (the SwiftData store) into `target` (an empty, prepared database) in one
 * transaction — a failure leaves `target` untouched so the import can simply be retried on the next launch.
 *
 * @param newId random UUID generator; rows that have no id of their own in SwiftData (programs, schedule
 *        entries, logged sets) get one here.
 */
export function importSwiftDataStore(source: Db, target: Db, newId: () => string): SwiftDataImportSummary {
  const summary: SwiftDataImportSummary = {
    programs: 0,
    workouts: 0,
    exercises: 0,
    scheduleEntries: 0,
    sessions: 0,
    loggedSets: 0,
    skipped: { scheduleEntries: 0, loggedSets: 0, orphans: 0 },
    reassignedExerciseIds: 0,
  };

  target.transaction(() => {
    // Programs have no UUID in SwiftData. Z_PK order stands in for creation order ("active" = first).
    const programIdByPk = new Map<number, string>();
    source
      .all<{ pk: number; name: string | null }>('SELECT Z_PK AS pk, ZNAME AS name FROM ZPERSISTEDPROGRAM ORDER BY Z_PK')
      .forEach((row, index) => {
        const id = newId();
        programIdByPk.set(row.pk, id);
        target.run('INSERT INTO Program(id, name, createdAtRowOrder) VALUES (?, ?, ?)', [id, row.name ?? 'My program', index + 1]);
        summary.programs += 1;
      });

    const workoutIdByPk = new Map<number, string>();
    for (const row of source.all<{ pk: number; program: number | null; name: string | null; id: string; sortOrder: number | null }>(
      'SELECT Z_PK AS pk, ZPROGRAM AS program, ZNAME AS name, lower(hex(ZID)) AS id, ZSORTORDER AS sortOrder FROM ZPERSISTEDWORKOUT ORDER BY Z_PK',
    )) {
      const programId = row.program == null ? undefined : programIdByPk.get(row.program);
      if (!programId) {
        summary.skipped.orphans += 1;
        continue;
      }
      const id = uuidFromHex(row.id);
      workoutIdByPk.set(row.pk, id);
      target.run('INSERT INTO Workout(id, programId, name, sortOrder) VALUES (?, ?, ?, ?)', [id, programId, row.name ?? 'Workout', row.sortOrder ?? 0]);
      summary.workouts += 1;
    }

    // The native importer could give two same-named exercises on one sheet the same carried-over id; ids are a
    // primary key here, so the later one gets a fresh id (its logged history stays with the first).
    const usedExerciseIds = new Set<string>();
    for (const row of source.all<{
      workout: number | null;
      id: string;
      name: string | null;
      sortOrder: number | null;
      setCount: number | null;
      note: string | null;
      repsArePerSide: number | null;
      kind: string | null;
    }>(
      `SELECT ZWORKOUT AS workout, lower(hex(ZID)) AS id, ZNAME AS name, ZSORTORDER AS sortOrder, ZSETCOUNT AS setCount,
              ZNOTE AS note, ZREPSAREPERSIDE AS repsArePerSide, ZKIND AS kind
       FROM ZPERSISTEDEXERCISE ORDER BY Z_PK`,
    )) {
      const workoutId = row.workout == null ? undefined : workoutIdByPk.get(row.workout);
      if (!workoutId) {
        summary.skipped.orphans += 1;
        continue;
      }
      let id = uuidFromHex(row.id);
      if (usedExerciseIds.has(id)) {
        id = newId();
        summary.reassignedExerciseIds += 1;
      }
      usedExerciseIds.add(id);
      target.run(
        'INSERT INTO Exercise(id, workoutId, name, sortOrder, setCount, note, repsArePerSide, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [id, workoutId, row.name ?? 'Exercise', row.sortOrder ?? 0, row.setCount ?? 1, row.note, row.repsArePerSide ? 1 : 0, row.kind === 'cardio' ? 'cardio' : 'strength'],
      );
      summary.exercises += 1;
    }

    // One row per calendar day; if the store ever held two for the same day the later one wins, as in the
    // native app's own schedule reads.
    const scheduleRows = source.all<{
      program: number | null;
      year: number;
      month: number;
      day: number;
      isRestDay: number | null;
      workoutId: string | null;
    }>(
      `SELECT ZPROGRAM AS program, ZYEAR AS year, ZMONTH AS month, ZDAY AS day, ZISRESTDAY AS isRestDay,
              lower(hex(ZWORKOUTID)) AS workoutId
       FROM ZPERSISTEDSCHEDULEENTRY ORDER BY Z_PK`,
    );
    const seenDays = new Set<string>();
    for (const row of scheduleRows) {
      const programId = row.program == null ? undefined : programIdByPk.get(row.program);
      if (!programId) {
        summary.skipped.orphans += 1;
        continue;
      }
      const dayKey = `${programId}/${row.year}-${row.month}-${row.day}`;
      if (seenDays.has(dayKey)) summary.skipped.scheduleEntries += 1;
      else summary.scheduleEntries += 1;
      seenDays.add(dayKey);
      const workoutId = row.workoutId ? uuidFromHex(row.workoutId) : null;
      const isRestDay = row.isRestDay || !workoutId ? 1 : 0;
      target.run(
        `INSERT INTO ScheduleEntry(id, programId, year, month, day, isRestDay, workoutId) VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(programId, year, month, day) DO UPDATE SET isRestDay = excluded.isRestDay, workoutId = excluded.workoutId`,
        [newId(), programId, row.year, row.month, row.day, isRestDay, isRestDay ? null : workoutId],
      );
    }

    const sessionIdByPk = new Map<number, string>();
    for (const row of source.all<{
      pk: number;
      id: string;
      templateId: string;
      year: number;
      month: number;
      day: number;
      isComplete: number | null;
      createdAt: number | null;
      completedAt: number | null;
      title: string | null;
      note: string | null;
    }>(
      `SELECT Z_PK AS pk, lower(hex(ZID)) AS id, lower(hex(ZWORKOUTTEMPLATEID)) AS templateId, ZSCHEDULEYEAR AS year,
              ZSCHEDULEMONTH AS month, ZSCHEDULEDAY AS day, ZISCOMPLETE AS isComplete, ZCREATEDAT AS createdAt,
              ZCOMPLETEDAT AS completedAt, ZWORKOUTTITLESNAPSHOT AS title, ZSESSIONNOTE AS note
       FROM ZPERSISTEDWORKOUTSESSION ORDER BY Z_PK`,
    )) {
      const id = uuidFromHex(row.id);
      sessionIdByPk.set(row.pk, id);
      target.run(
        `INSERT INTO WorkoutSession(id, workoutTemplateId, scheduleYear, scheduleMonth, scheduleDay, isComplete,
                                    createdAt, completedAt, workoutTitleSnapshot, sessionNote)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          id,
          uuidFromHex(row.templateId),
          row.year,
          row.month,
          row.day,
          row.isComplete ? 1 : 0,
          epochMillisFromCoreDataDate(row.createdAt ?? 0),
          row.completedAt == null ? null : epochMillisFromCoreDataDate(row.completedAt),
          row.title,
          row.note,
        ],
      );
      summary.sessions += 1;
    }

    // (session, exercise, set) is unique here. Entered rows are imported first so that, if the store holds two
    // rows for one slot, the one the user actually typed is the one that survives.
    for (const row of source.all<{
      session: number | null;
      exerciseId: string;
      setIndex: number;
      weight: number | null;
      reps: number | null;
      seeded: number | null;
      edited: number | null;
      perSide: number | null;
      cardioMinutes: number | null;
      maxHeartRate: number | null;
    }>(
      `SELECT ZSESSION AS session, lower(hex(ZEXERCISEID)) AS exerciseId, ZSETINDEX AS setIndex, ZWEIGHT AS weight,
              ZREPS AS reps, ZSEEDEDFROMCARRYOVER AS seeded, ZUSEREDITEDVALUES AS edited, ZREPSAREPERSIDE AS perSide,
              ZCARDIOMINUTES AS cardioMinutes, ZMAXHEARTRATE AS maxHeartRate
       FROM ZPERSISTEDLOGGEDSET ORDER BY ZUSEREDITEDVALUES DESC, Z_PK`,
    )) {
      const sessionId = row.session == null ? undefined : sessionIdByPk.get(row.session);
      if (!sessionId) {
        summary.skipped.orphans += 1;
        continue;
      }
      const exerciseId = uuidFromHex(row.exerciseId);
      const taken = target.first<{ one: number }>(
        'SELECT 1 AS one FROM LoggedSet WHERE sessionId = ? AND exerciseId = ? AND setIndex = ?',
        [sessionId, exerciseId, row.setIndex],
      );
      if (taken) {
        summary.skipped.loggedSets += 1;
        continue;
      }
      target.run(
        `INSERT INTO LoggedSet(id, sessionId, exerciseId, setIndex, weight, reps, seededFromCarryover, userEditedValues,
                               repsArePerSide, cardioMinutes, maxHeartRate)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          newId(),
          sessionId,
          exerciseId,
          row.setIndex,
          row.weight ?? 0,
          row.reps ?? 0,
          row.seeded ? 1 : 0,
          row.edited ? 1 : 0,
          row.perSide ? 1 : 0,
          row.cardioMinutes ?? 0,
          row.maxHeartRate ?? 0,
        ],
      );
      summary.loggedSets += 1;
    }
  });

  return summary;
}

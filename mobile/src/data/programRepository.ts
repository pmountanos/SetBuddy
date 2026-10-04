import { addDays, type CalendarDate, dateKey } from '../domain/calendarDate';
import type { ExistingExercise } from '../domain/carryoverMatcher';
import type { ExerciseKind } from '../domain/exerciseKind';
import { type DayPlan, ProgramCalendarSchedule, REST, sameDayPlan, workoutPlan } from '../domain/schedule';
import { compareWorkouts } from '../domain/workoutDisplaySort';
import type { Db } from './db';
import { type Env, type Exercise, type ExerciseRow, exerciseFromRow, type Program, type Workout } from './models';

/** Days of calendar rows kept ahead of today (rest until assigned); matches the spreadsheet import horizon. */
export const FORWARD_SCHEDULE_HORIZON_DAYS = 196;

/**
 * How many days ahead `setScheduleDayShiftingFollowing` looks for the value already recurring, to swap to it
 * (bounded rotation) instead of inserting a duplicate and shifting the whole remaining horizon. Generous upper
 * bound on realistic workout-rotation cycle lengths.
 */
export const NEAR_DUPLICATE_SEARCH_WINDOW = 60;

export const DEFAULT_SET_COUNT = 4;

interface ScheduleRow {
  year: number;
  month: number;
  day: number;
  isRestDay: number;
  workoutId: string | null;
}

const planFromRow = (row: ScheduleRow | undefined): DayPlan =>
  !row || row.isRestDay === 1 || !row.workoutId ? REST : workoutPlan(row.workoutId);

export class ProgramRepository {
  constructor(
    private readonly db: Db,
    private readonly env: Env,
  ) {}

  /** The one active program (the oldest, if the store ever held more than one). */
  activeProgram(): Program | null {
    return this.db.first<Program>('SELECT id, name FROM Program ORDER BY createdAtRowOrder ASC LIMIT 1');
  }

  /** Workouts in display/picker order. */
  workouts(programId: string): Workout[] {
    return this.db
      .all<Workout>('SELECT id, programId, name, sortOrder FROM Workout WHERE programId = ?', [programId])
      .sort(compareWorkouts);
  }

  workout(id: string): Workout | null {
    return this.db.first<Workout>('SELECT id, programId, name, sortOrder FROM Workout WHERE id = ?', [id]);
  }

  exercises(workoutId: string): Exercise[] {
    return this.db
      .all<ExerciseRow>('SELECT * FROM Exercise WHERE workoutId = ? ORDER BY sortOrder', [workoutId])
      .map(exerciseFromRow);
  }

  /** Active program's exercises, for carry-over matching before a re-import replaces the program. */
  existingExercisesForCarryover(): ExistingExercise[] {
    const program = this.activeProgram();
    if (!program) return [];
    return this.db.all<ExistingExercise>(
      `SELECT Exercise.id, Exercise.name FROM Exercise
       INNER JOIN Workout ON Workout.id = Exercise.workoutId WHERE Workout.programId = ?
       ORDER BY Workout.sortOrder, Exercise.sortOrder`,
      [program.id],
    );
  }

  private scheduleRows(programId: string): ScheduleRow[] {
    return this.db.all<ScheduleRow>(
      'SELECT year, month, day, isRestDay, workoutId FROM ScheduleEntry WHERE programId = ? ORDER BY year, month, day',
      [programId],
    );
  }

  calendarSchedule(programId: string): ProgramCalendarSchedule {
    const schedule = new ProgramCalendarSchedule();
    for (const row of this.scheduleRows(programId)) {
      schedule.set({ year: row.year, month: row.month, day: row.day }, planFromRow(row));
    }
    return schedule;
  }

  workoutTitles(programId: string): Map<string, string> {
    return new Map(this.workouts(programId).map((w) => [w.id, w.name]));
  }

  /** Makes sure every day from today through the horizon has a schedule row (rest until assigned). */
  ensureForwardScheduleFilled(daysAhead = FORWARD_SCHEDULE_HORIZON_DAYS): void {
    const program = this.activeProgram();
    if (!program) return;
    const today = this.env.today();
    const existing = new Set(this.scheduleRows(program.id).map(dateKey));
    this.db.transaction(() => {
      for (let offset = 0; offset < daysAhead; offset++) {
        const date = addDays(today, offset);
        if (!existing.has(dateKey(date))) this.applyScheduleDay(program.id, date, REST);
      }
    });
  }

  /** Creates the only program when the store is empty: one starter workout with one exercise, plus a forward schedule (all rest until workouts are assigned). */
  createFirstProgram(name: string): Program {
    if (this.activeProgram()) throw new Error('A program already exists');
    const program: Program = { id: this.env.newId(), name: name.trim() || 'My program' };
    const workoutId = this.env.newId();
    this.db.transaction(() => {
      this.insertProgram(program);
      this.db.run('INSERT INTO Workout(id, programId, name, sortOrder) VALUES (?, ?, ?, 0)', [workoutId, program.id, 'Workout 1']);
      this.insertExercise({ workoutId, name: 'Exercise 1', sortOrder: 0, setCount: DEFAULT_SET_COUNT });
    });
    this.ensureForwardScheduleFilled();
    return program;
  }

  /** Replaces the program and schedule with a fresh starter. Completed sessions stay in History; any in-progress session is cleared. */
  startOverFreshProgram(name: string): Program {
    this.db.transaction(() => this.removeAllProgramsPreservingCompletedHistory());
    return this.createFirstProgram(name);
  }

  /**
   * Wipes every program (workouts/exercises/schedule cascade) ahead of a replacement. First backfills
   * `workoutTitleSnapshot` on sessions that lack one, so History stays readable once the templates are gone,
   * and drops in-progress sessions since their template is about to disappear. Call inside a transaction.
   */
  removeAllProgramsPreservingCompletedHistory(): void {
    this.db.run(
      `UPDATE WorkoutSession SET workoutTitleSnapshot = (SELECT name FROM Workout WHERE Workout.id = WorkoutSession.workoutTemplateId)
       WHERE workoutTitleSnapshot IS NULL`,
    );
    this.db.run('DELETE FROM WorkoutSession WHERE isComplete = 0');
    this.db.run('DELETE FROM Program');
  }

  insertProgram(program: Program): void {
    const next = this.db.first<{ next: number }>('SELECT IFNULL(MAX(createdAtRowOrder), 0) + 1 AS next FROM Program')!.next;
    this.db.run('INSERT INTO Program(id, name, createdAtRowOrder) VALUES (?, ?, ?)', [program.id, program.name, next]);
  }

  insertExercise(exercise: {
    id?: string;
    workoutId: string;
    name: string;
    sortOrder: number;
    setCount: number;
    note?: string | null;
    repsArePerSide?: boolean;
    kind?: ExerciseKind;
  }): string {
    const id = exercise.id ?? this.env.newId();
    this.db.run(
      'INSERT INTO Exercise(id, workoutId, name, sortOrder, setCount, note, repsArePerSide, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [id, exercise.workoutId, exercise.name, exercise.sortOrder, exercise.setCount, exercise.note ?? null, exercise.repsArePerSide ? 1 : 0, exercise.kind ?? 'strength'],
    );
    return id;
  }

  renameProgram(name: string): void {
    const program = this.activeProgram();
    const trimmed = name.trim();
    if (!program || !trimmed) return;
    this.db.run('UPDATE Program SET name = ? WHERE id = ?', [trimmed, program.id]);
  }

  renameWorkout(id: string, name: string): void {
    const trimmed = name.trim();
    if (trimmed) this.db.run('UPDATE Workout SET name = ? WHERE id = ?', [trimmed, id]);
  }

  /** Sets one day without touching any other. */
  setScheduleDay(date: CalendarDate, plan: DayPlan): void {
    const program = this.activeProgram();
    if (program) this.applyScheduleDay(program.id, date, plan);
  }

  /**
   * Assigns `plan` to `from` and shifts every day after it forward by one, keeping the relative order of later
   * workouts/rest days after one day is realigned (e.g. after a missed session).
   *
   * @param options.skipIfUnchanged when `true` (default), does nothing if `from` already has `plan` (picker
   *        no-op). **Add a rest day** passes `false` so inserting rest still pushes the schedule even when that
   *        day was already rest.
   * @param options.preferNearestRecurrence when `true` (default) and `plan` already recurs within the next
   *        {@link NEAR_DUPLICATE_SEARCH_WINDOW} days, rotates just that bounded window (`from` through the
   *        recurrence) instead of shifting the entire remaining horizon. Pass `false` for an unconditional insert.
   */
  setScheduleDayShiftingFollowing(
    from: CalendarDate,
    plan: DayPlan,
    options: { cascadeDays?: number; skipIfUnchanged?: boolean; preferNearestRecurrence?: boolean } = {},
  ): void {
    const { cascadeDays = FORWARD_SCHEDULE_HORIZON_DAYS, skipIfUnchanged = true, preferNearestRecurrence = true } = options;
    const program = this.activeProgram();
    if (!program) return;
    const existing = new Map(this.scheduleRows(program.id).map((row) => [dateKey(row), row]));

    // Days with no row yet (past the stored horizon) count as rest.
    const oldPlans: DayPlan[] = [];
    for (let offset = 0; offset <= cascadeDays; offset++) {
      oldPlans.push(planFromRow(existing.get(dateKey(addDays(from, offset)))));
    }
    if (skipIfUnchanged && sameDayPlan(oldPlans[0], plan)) return;

    // If `plan` already recurs soon (e.g. pulling a workout that's due again in a few days to today, rather
    // than genuinely inserting something new), rotate just that bounded window instead of shifting the entire
    // rest of the horizon. Otherwise that recurrence shows up again a few days later as an apparent
    // duplicate/out-of-order repeat, and every day after it runs one calendar day later than the spreadsheet's
    // actual cycle from then on — compounding with every such edit. Bounded to a search window so a
    // coincidental match far in the future still falls through to a plain insert.
    let shiftThrough = cascadeDays;
    if (preferNearestRecurrence) {
      for (let offset = 1; offset <= Math.min(NEAR_DUPLICATE_SEARCH_WINDOW, cascadeDays); offset++) {
        if (sameDayPlan(oldPlans[offset], plan)) {
          shiftThrough = offset;
          break;
        }
      }
    }

    this.db.transaction(() => {
      this.applyScheduleDay(program.id, from, plan);
      // Day N's old plan moves to day N+1, through the recurrence if there is one, else the whole horizon.
      for (let offset = 1; offset <= shiftThrough; offset++) {
        this.applyScheduleDay(program.id, addDays(from, offset), oldPlans[offset - 1]);
      }
    });
  }

  /** Always inserts a genuinely new rest day — never swaps to a rest day that's already coming up soon, since "add a rest day" specifically means one more day off, not a rearrangement. */
  insertRestDayShiftingFollowing(start: CalendarDate, cascadeDays = FORWARD_SCHEDULE_HORIZON_DAYS): void {
    this.setScheduleDayShiftingFollowing(start, REST, { cascadeDays, skipIfUnchanged: false, preferNearestRecurrence: false });
  }

  applyScheduleDay(programId: string, date: CalendarDate, plan: DayPlan): void {
    this.db.run(
      `INSERT INTO ScheduleEntry(id, programId, year, month, day, isRestDay, workoutId) VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(programId, year, month, day) DO UPDATE SET isRestDay = excluded.isRestDay, workoutId = excluded.workoutId`,
      [this.env.newId(), programId, date.year, date.month, date.day, plan.type === 'rest' ? 1 : 0, plan.type === 'workout' ? plan.workoutId : null],
    );
  }

  /** Appends a workout after the existing ones. */
  addWorkout(name = 'New workout'): Workout {
    const program = this.activeProgram();
    if (!program) throw new Error('No active program');
    const sortOrder = this.db.first<{ next: number }>('SELECT IFNULL(MAX(sortOrder), -1) + 1 AS next FROM Workout WHERE programId = ?', [program.id])!.next;
    const workout: Workout = { id: this.env.newId(), programId: program.id, name: name.trim() || 'New workout', sortOrder };
    this.db.run('INSERT INTO Workout(id, programId, name, sortOrder) VALUES (?, ?, ?, ?)', [workout.id, workout.programId, workout.name, workout.sortOrder]);
    return workout;
  }

  /** Deletes a workout and its exercises; scheduled days that used it become rest days. */
  deleteWorkout(id: string): void {
    this.db.transaction(() => {
      this.db.run('UPDATE ScheduleEntry SET isRestDay = 1, workoutId = NULL WHERE workoutId = ?', [id]);
      this.db.run('DELETE FROM Workout WHERE id = ?', [id]);
    });
  }

  addExercise(workoutId: string, name = 'New exercise', setCount = DEFAULT_SET_COUNT): string {
    const next = this.db.first<{ next: number }>('SELECT IFNULL(MAX(sortOrder), -1) + 1 AS next FROM Exercise WHERE workoutId = ?', [workoutId])!.next;
    return this.insertExercise({ workoutId, name, sortOrder: next, setCount });
  }

  deleteExercise(id: string): void {
    this.db.run('DELETE FROM Exercise WHERE id = ?', [id]);
  }

  setExerciseName(id: string, name: string): void {
    const trimmed = name.trim();
    if (trimmed) this.db.run('UPDATE Exercise SET name = ? WHERE id = ?', [trimmed, id]);
  }

  /** Clamped to 1…20. */
  setExerciseSetCount(id: string, setCount: number): void {
    this.db.run('UPDATE Exercise SET setCount = ? WHERE id = ?', [Math.max(1, Math.min(20, Math.round(setCount))), id]);
  }

  setExerciseRepsPerSide(id: string, value: boolean): void {
    this.db.run('UPDATE Exercise SET repsArePerSide = ? WHERE id = ?', [value ? 1 : 0, id]);
  }

  /**
   * Switching to cardio resets the set count to **1** — a cardio exercise is normally a single set (one
   * duration/heart-rate reading), not a strength-style multi-set default. Still adjustable afterward.
   */
  setExerciseKind(id: string, kind: ExerciseKind): void {
    this.db.transaction(() => {
      this.db.run('UPDATE Exercise SET kind = ? WHERE id = ?', [kind, id]);
      if (kind === 'cardio') this.db.run('UPDATE Exercise SET setCount = 1 WHERE id = ?', [id]);
    });
  }

  /** Trims, and stores an empty note as none. */
  setExerciseNote(id: string, note: string | null): void {
    const trimmed = note?.trim() ?? '';
    this.db.run('UPDATE Exercise SET note = ? WHERE id = ?', [trimmed || null, id]);
  }

  reorderExercises(orderedExerciseIds: string[]): void {
    this.db.transaction(() => {
      orderedExerciseIds.forEach((id, index) => this.db.run('UPDATE Exercise SET sortOrder = ? WHERE id = ?', [index, id]));
    });
  }
}

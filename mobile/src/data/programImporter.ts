import { addDays, type CalendarDate } from '../domain/calendarDate';
import { type ImportedCycleDay, refKey } from '../domain/carryoverMatcher';
import { REST, workoutPlan } from '../domain/schedule';
import { DEFAULT_SET_COUNT_PER_EXERCISE, ProgramImportError } from '../xlsx/programXlsxParser';
import type { Db } from './db';
import type { Env } from './models';
import { FORWARD_SCHEDULE_HORIZON_DAYS, ProgramRepository } from './programRepository';

export interface ProgramImportOptions {
  programName: string;
  /** The calendar day the cycle starts on. */
  startDate: CalendarDate;
  /** Which `cycle` entry (0-based, workbook tab order) lands on `startDate`. */
  cycleStartIndex?: number;
  horizonDays?: number;
  /** Pre-resolved carry-over: `refKey(sheet, exercise name)` → the existing exercise id to keep. */
  exerciseCarryover?: ReadonlyMap<string, string>;
}

/**
 * Replaces the program (workouts, exercises, schedule) with one built from a parsed workbook. Completed
 * sessions survive with their title snapshot; in-progress sessions are dropped since their template is going
 * away. Runs as one transaction, so a failed import leaves the previous program in place.
 */
export function importProgramReplacingStore(db: Db, env: Env, cycle: ImportedCycleDay[], options: ProgramImportOptions): void {
  const { programName, startDate, cycleStartIndex = 0, horizonDays = FORWARD_SCHEDULE_HORIZON_DAYS, exerciseCarryover = new Map() } = options;
  const period = cycle.length;
  if (period === 0) throw new ProgramImportError('The workbook has no worksheets.');
  const programs = new ProgramRepository(db, env);

  db.transaction(() => {
    programs.removeAllProgramsPreservingCompletedHistory();
    const programId = env.newId();
    programs.insertProgram({ id: programId, name: programName });

    // A sheet can repeat an exercise name (e.g. a copy-paste duplicate); both rows then resolve to the same
    // carried-over id, which would violate Exercise's primary key. Only the first keeps it.
    const carriedOverIds = new Set<string>();
    const workoutIdBySheet = new Map<string, string>();
    for (const day of cycle) {
      if (day.isRestDay || workoutIdBySheet.has(day.sheetName)) continue;
      const workoutId = env.newId();
      // First-encountered order in the cycle (interleaved, e.g. Push 1, Cardio 1, Pull 1, ...) drives
      // display/picker order, rather than the Push/Pull/Legs-only naming heuristic.
      db.run('INSERT INTO Workout(id, programId, name, sortOrder) VALUES (?, ?, ?, ?)', [workoutId, programId, day.sheetName, workoutIdBySheet.size]);
      workoutIdBySheet.set(day.sheetName, workoutId);
      day.exercises.forEach((exercise, index) => {
        const carried = exerciseCarryover.get(refKey({ workoutSheetName: day.sheetName, exerciseName: exercise.name }));
        const id = carried && !carriedOverIds.has(carried) ? carried : env.newId();
        carriedOverIds.add(id);
        programs.insertExercise({
          id,
          workoutId,
          name: exercise.name,
          sortOrder: index,
          // Cardio defaults to a single set (one duration/heart-rate reading), not the strength default.
          setCount: exercise.kind === 'cardio' ? 1 : DEFAULT_SET_COUNT_PER_EXERCISE,
          note: exercise.note,
          repsArePerSide: exercise.repsArePerSide,
          kind: exercise.kind,
        });
      });
    }

    const startIndex = ((cycleStartIndex % period) + period) % period;
    for (let offset = 0; offset < horizonDays; offset++) {
      const slot = cycle[(offset + startIndex) % period];
      const workoutId = slot.isRestDay ? undefined : workoutIdBySheet.get(slot.sheetName);
      programs.applyScheduleDay(programId, addDays(startDate, offset), workoutId ? workoutPlan(workoutId) : REST);
    }
  });
}

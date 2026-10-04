import type { CalendarDate } from '../domain/calendarDate';
import type { Db } from './db';
import type { Env, Exercise } from './models';
import { ProgramRepository } from './programRepository';

export interface ProgramWorkoutOutline {
  id: string;
  name: string;
  exercises: Exercise[];
}

export interface ProgramOutline {
  programId: string;
  programName: string;
  /** In display/picker order. */
  workouts: ProgramWorkoutOutline[];
}

export interface ProgramScheduleDayRow {
  date: CalendarDate;
  isRestDay: boolean;
  workoutId: string | null;
  workoutTitle: string | null;
}

export class ProgramOutlineRepository {
  private readonly programs: ProgramRepository;

  constructor(
    private readonly db: Db,
    private readonly env: Env,
  ) {
    this.programs = new ProgramRepository(db, env);
  }

  activeProgramOutline(): ProgramOutline | null {
    const program = this.programs.activeProgram();
    if (!program) return null;
    const workouts = this.programs
      .workouts(program.id)
      .map((workout) => ({ id: workout.id, name: workout.name, exercises: this.programs.exercises(workout.id) }));
    return { programId: program.id, programName: program.name, workouts };
  }

  /** The next `limit` scheduled days from today on. */
  upcomingScheduleRows(limit: number): ProgramScheduleDayRow[] {
    const program = this.programs.activeProgram();
    if (!program) return [];
    const today = this.env.today();
    const titles = this.programs.workoutTitles(program.id);
    return this.db
      .all<{ year: number; month: number; day: number; isRestDay: number; workoutId: string | null }>(
        `SELECT year, month, day, isRestDay, workoutId FROM ScheduleEntry
         WHERE programId = ? AND (year, month, day) >= (?, ?, ?) ORDER BY year, month, day LIMIT ?`,
        [program.id, today.year, today.month, today.day, limit],
      )
      .map((entry) => {
        const isRestDay = entry.isRestDay === 1 || !entry.workoutId;
        return {
          date: { year: entry.year, month: entry.month, day: entry.day },
          isRestDay,
          workoutId: isRestDay ? null : entry.workoutId,
          workoutTitle: isRestDay ? null : (titles.get(entry.workoutId!) ?? null),
        };
      });
  }
}

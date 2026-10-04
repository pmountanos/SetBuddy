import type { CalendarDate } from '../domain/calendarDate';
import { type ExerciseKind, exerciseKindFromRaw } from '../domain/exerciseKind';

/** Things the data layer needs from the outside world; injected so tests control ids, the clock and "today". */
export interface Env {
  newId(): string;
  /** Epoch milliseconds. */
  now(): number;
  today(): CalendarDate;
}

export interface Program {
  id: string;
  name: string;
}

export interface Workout {
  id: string;
  programId: string;
  name: string;
  sortOrder: number;
}

export interface Exercise {
  id: string;
  workoutId: string;
  name: string;
  sortOrder: number;
  /** Number of sets to log for this exercise in a session. */
  setCount: number;
  note: string | null;
  /** Logged reps are per side (e.g. dumbbell); volume for each set counts both sides (×2). */
  repsArePerSide: boolean;
  kind: ExerciseKind;
}

export interface WorkoutSession {
  id: string;
  workoutTemplateId: string;
  scheduleDate: CalendarDate;
  isComplete: boolean;
  createdAt: number;
  completedAt: number | null;
  /** Workout name at completion time so history stays correct after a re-import removes old templates. */
  workoutTitleSnapshot: string | null;
  sessionNote: string | null;
}

export interface LoggedSet {
  exerciseId: string;
  setIndex: number;
  weight: number;
  reps: number;
  cardioMinutes: number;
  maxHeartRate: number;
  /** True once the user has entered this set; only entered sets survive finishing the workout. */
  userEditedValues: boolean;
  repsArePerSide: boolean;
}

export interface ExerciseRow {
  id: string;
  workoutId: string;
  name: string;
  sortOrder: number;
  setCount: number;
  note: string | null;
  repsArePerSide: number;
  kind: string;
}

export interface SessionRow {
  id: string;
  workoutTemplateId: string;
  scheduleYear: number;
  scheduleMonth: number;
  scheduleDay: number;
  isComplete: number;
  createdAt: number;
  completedAt: number | null;
  workoutTitleSnapshot: string | null;
  sessionNote: string | null;
}

export interface LoggedSetRow {
  exerciseId: string;
  setIndex: number;
  weight: number;
  reps: number;
  cardioMinutes: number;
  maxHeartRate: number;
  userEditedValues: number;
  repsArePerSide: number;
}

export const exerciseFromRow = (row: ExerciseRow): Exercise => ({
  ...row,
  repsArePerSide: row.repsArePerSide === 1,
  kind: exerciseKindFromRaw(row.kind),
});

export const sessionFromRow = (row: SessionRow): WorkoutSession => ({
  id: row.id,
  workoutTemplateId: row.workoutTemplateId,
  scheduleDate: { year: row.scheduleYear, month: row.scheduleMonth, day: row.scheduleDay },
  isComplete: row.isComplete === 1,
  createdAt: row.createdAt,
  completedAt: row.completedAt,
  workoutTitleSnapshot: row.workoutTitleSnapshot,
  sessionNote: row.sessionNote,
});

export const loggedSetFromRow = (row: LoggedSetRow): LoggedSet => ({
  exerciseId: row.exerciseId,
  setIndex: row.setIndex,
  weight: row.weight,
  reps: row.reps,
  cardioMinutes: row.cardioMinutes,
  maxHeartRate: row.maxHeartRate,
  userEditedValues: row.userEditedValues === 1,
  repsArePerSide: row.repsArePerSide === 1,
});

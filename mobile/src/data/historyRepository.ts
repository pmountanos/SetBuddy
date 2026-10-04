import type { CalendarDate } from '../domain/calendarDate';
import type { ExerciseKind } from '../domain/exerciseKind';
import { exerciseKindFromRaw } from '../domain/exerciseKind';
import { setVolume } from '../domain/volume';
import type { Db } from './db';
import type { LoggedSetRow, SessionRow } from './models';

export interface HistoryCompletedRow {
  sessionId: string;
  title: string;
  completedAt: number;
  totalVolume: number;
  hasSessionNote: boolean;
}

export interface HistorySetLine {
  setNumber: number;
  weight: number;
  reps: number;
  repsArePerSide: boolean;
  kind: ExerciseKind;
  cardioMinutes: number;
  maxHeartRate: number;
  /** Cardio sets don't count toward weight × reps volume. */
  volume: number;
}

export interface HistoryExerciseGroup {
  exerciseId: string;
  name: string;
  kind: ExerciseKind;
  sets: HistorySetLine[];
  volume: number;
  /** Total minutes, for cardio exercises. */
  cardioMinutes: number;
}

export interface HistorySessionDetail {
  sessionId: string;
  title: string;
  completedAt: number;
  scheduleDate: CalendarDate;
  sessionNote: string | null;
  exercises: HistoryExerciseGroup[];
  totalVolume: number;
}

export class HistoryRepository {
  constructor(private readonly db: Db) {}

  /** Snapshot taken at completion, else the template's current name if it still exists. */
  private title(session: SessionRow): string {
    return (
      session.workoutTitleSnapshot ??
      this.db.first<{ name: string }>('SELECT name FROM Workout WHERE id = ?', [session.workoutTemplateId])?.name ??
      'Workout'
    );
  }

  /** Completed sessions, newest first. */
  completedRows(limit = 50): HistoryCompletedRow[] {
    return this.db
      .all<SessionRow>('SELECT * FROM WorkoutSession WHERE isComplete = 1 ORDER BY completedAt DESC LIMIT ?', [limit])
      .map((session) => ({
        sessionId: session.id,
        title: this.title(session),
        completedAt: session.completedAt ?? 0,
        totalVolume: this.sessionDetail(session.id)?.totalVolume ?? 0,
        hasSessionNote: !!session.sessionNote?.trim(),
      }));
  }

  sessionDetail(sessionId: string): HistorySessionDetail | null {
    const session = this.db.first<SessionRow>('SELECT * FROM WorkoutSession WHERE id = ?', [sessionId]);
    if (!session) return null;
    const rows = this.db.all<LoggedSetRow>('SELECT * FROM LoggedSet WHERE sessionId = ? ORDER BY setIndex', [sessionId]);

    // Name/kind/order come from the exercise as it exists now; one deleted since (e.g. a re-import that didn't
    // carry it over) falls back to "Exercise" / strength and sorts after the known ones.
    const groups = new Map<string, HistoryExerciseGroup & { order: number }>();
    for (const row of rows) {
      let group = groups.get(row.exerciseId);
      if (!group) {
        const exercise = this.db.first<{ name: string; kind: string; sortOrder: number }>(
          'SELECT name, kind, sortOrder FROM Exercise WHERE id = ?',
          [row.exerciseId],
        );
        group = {
          exerciseId: row.exerciseId,
          name: exercise?.name ?? 'Exercise',
          kind: exerciseKindFromRaw(exercise?.kind),
          sets: [],
          volume: 0,
          cardioMinutes: 0,
          order: exercise?.sortOrder ?? Number.MAX_SAFE_INTEGER,
        };
        groups.set(row.exerciseId, group);
      }
      const repsArePerSide = row.repsArePerSide === 1;
      const volume = group.kind === 'cardio' ? 0 : setVolume(row.weight, row.reps, repsArePerSide);
      group.sets.push({
        setNumber: row.setIndex + 1,
        weight: row.weight,
        reps: row.reps,
        repsArePerSide,
        kind: group.kind,
        cardioMinutes: row.cardioMinutes,
        maxHeartRate: row.maxHeartRate,
        volume,
      });
      group.volume += volume;
      group.cardioMinutes += row.cardioMinutes;
    }

    const exercises = [...groups.values()]
      .sort((a, b) => a.order - b.order || a.exerciseId.localeCompare(b.exerciseId))
      .map(({ order: _order, ...group }) => group);

    return {
      sessionId: session.id,
      title: this.title(session),
      completedAt: session.completedAt ?? 0,
      scheduleDate: { year: session.scheduleYear, month: session.scheduleMonth, day: session.scheduleDay },
      sessionNote: session.sessionNote,
      exercises,
      totalVolume: exercises.reduce((sum, group) => sum + group.volume, 0),
    };
  }

  /** Every completed session in full, newest first — for export. */
  allCompletedSessionDetails(): HistorySessionDetail[] {
    return this.db
      .all<{ id: string }>('SELECT id FROM WorkoutSession WHERE isComplete = 1 ORDER BY completedAt DESC')
      .map((row) => this.sessionDetail(row.id)!)
      .filter(Boolean);
  }
}

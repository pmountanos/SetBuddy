import type { CalendarDate } from '../domain/calendarDate';
import type { Db } from './db';
import {
  type Env,
  type ExerciseRow,
  type LoggedSet,
  loggedSetFromRow,
  type LoggedSetRow,
  sessionFromRow,
  type SessionRow,
  type WorkoutSession,
} from './models';

export class WorkoutSessionRepository {
  constructor(
    private readonly db: Db,
    private readonly env: Env,
  ) {}

  private sessionForDay(templateId: string, day: CalendarDate, isComplete: boolean): WorkoutSession | null {
    const row = this.db.first<SessionRow>(
      `SELECT * FROM WorkoutSession
       WHERE workoutTemplateId = ? AND scheduleYear = ? AND scheduleMonth = ? AND scheduleDay = ? AND isComplete = ?
       ORDER BY createdAt DESC LIMIT 1`,
      [templateId, day.year, day.month, day.day, isComplete ? 1 : 0],
    );
    return row ? sessionFromRow(row) : null;
  }

  /** The in-progress session for this workout on this day, if any. */
  activeSession(templateId: string, day: CalendarDate): WorkoutSession | null {
    return this.sessionForDay(templateId, day, false);
  }

  hasCompletedSession(templateId: string, day: CalendarDate): boolean {
    return this.sessionForDay(templateId, day, true) !== null;
  }

  session(id: string): WorkoutSession | null {
    const row = this.db.first<SessionRow>('SELECT * FROM WorkoutSession WHERE id = ?', [id]);
    return row ? sessionFromRow(row) : null;
  }

  /** Returns the in-progress session for the workout/day, creating it (and its logged-set rows) if needed. */
  getOrCreateActiveSession(templateId: string, day: CalendarDate): WorkoutSession {
    let session = this.activeSession(templateId, day);
    if (!session) {
      const id = this.env.newId();
      this.db.run(
        `INSERT INTO WorkoutSession(id, workoutTemplateId, scheduleYear, scheduleMonth, scheduleDay, isComplete, createdAt)
         VALUES (?, ?, ?, ?, ?, 0, ?)`,
        [id, templateId, day.year, day.month, day.day, this.env.now()],
      );
      session = this.session(id)!;
    }
    this.syncLoggedSetsToTemplate(session);
    return session;
  }

  /** Adds missing logged-set rows and removes rows beyond the template's current set count. */
  private syncLoggedSetsToTemplate(session: WorkoutSession): void {
    const exercises = this.db.all<ExerciseRow>('SELECT * FROM Exercise WHERE workoutId = ?', [session.workoutTemplateId]);
    this.db.transaction(() => {
      for (const exercise of exercises) {
        for (let setIndex = 0; setIndex < exercise.setCount; setIndex++) {
          this.db.run(
            'INSERT OR IGNORE INTO LoggedSet(id, sessionId, exerciseId, setIndex, repsArePerSide) VALUES (?, ?, ?, ?, ?)',
            [this.env.newId(), session.id, exercise.id, setIndex, exercise.repsArePerSide],
          );
        }
        this.db.run('DELETE FROM LoggedSet WHERE sessionId = ? AND exerciseId = ? AND setIndex >= ?', [session.id, exercise.id, exercise.setCount]);
      }
    });
  }

  loggedSets(sessionId: string): LoggedSet[] {
    return this.db
      .all<LoggedSetRow>('SELECT * FROM LoggedSet WHERE sessionId = ? ORDER BY exerciseId, setIndex', [sessionId])
      .map(loggedSetFromRow);
  }

  /**
   * Most recent entered value **per exercise, any workout**, from completed sessions — shown as the reference
   * while logging. Keyed by exercise id, then set index.
   */
  mostRecentLoggedValuesByExercise(): Map<string, Map<number, LoggedSet>> {
    const result = new Map<string, Map<number, LoggedSet>>();
    const rows = this.db.all<LoggedSetRow>(
      `SELECT ls.* FROM LoggedSet ls INNER JOIN WorkoutSession ws ON ws.id = ls.sessionId
       WHERE ws.isComplete = 1 ORDER BY ws.completedAt DESC`,
    );
    for (const row of rows) {
      let bucket = result.get(row.exerciseId);
      if (!bucket) result.set(row.exerciseId, (bucket = new Map()));
      if (!bucket.has(row.setIndex)) bucket.set(row.setIndex, loggedSetFromRow(row));
    }
    return result;
  }

  /** Records weight/reps for a set and marks it as entered. */
  updateLoggedSet(sessionId: string, exerciseId: string, setIndex: number, weight: number, reps: number): void {
    this.db.run(
      'UPDATE LoggedSet SET weight = ?, reps = ?, userEditedValues = 1 WHERE sessionId = ? AND exerciseId = ? AND setIndex = ?',
      [Math.max(0, weight), Math.max(0, Math.trunc(reps)), sessionId, exerciseId, setIndex],
    );
  }

  /** Cardio counterpart of `updateLoggedSet` — records minutes/max heart rate instead of weight/reps. */
  updateCardioLoggedSet(sessionId: string, exerciseId: string, setIndex: number, minutes: number, maxHeartRate: number): void {
    this.db.run(
      'UPDATE LoggedSet SET cardioMinutes = ?, maxHeartRate = ?, userEditedValues = 1 WHERE sessionId = ? AND exerciseId = ? AND setIndex = ?',
      [Math.max(0, minutes), Math.max(0, Math.trunc(maxHeartRate)), sessionId, exerciseId, setIndex],
    );
  }

  /**
   * Drops rows the user never entered — or entered and then cleared back to nothing — snapshots the workout
   * title, and marks the session complete.
   */
  completeSession(sessionId: string, workoutTitle: string): void {
    this.db.transaction(() => {
      this.db.run(
        `DELETE FROM LoggedSet WHERE sessionId = ?
         AND (userEditedValues = 0 OR (weight = 0 AND reps = 0 AND cardioMinutes = 0 AND maxHeartRate = 0))`,
        [sessionId],
      );
      this.db.run('UPDATE WorkoutSession SET isComplete = 1, completedAt = ?, workoutTitleSnapshot = ? WHERE id = ?', [this.env.now(), workoutTitle, sessionId]);
    });
  }

  /** Undoes `completeSession` for the given day (e.g. Finish tapped by accident); rows dropped at completion are re-created by `getOrCreateActiveSession`. */
  reopenCompletedSession(templateId: string, day: CalendarDate): void {
    this.db.run(
      `UPDATE WorkoutSession SET isComplete = 0, completedAt = NULL
       WHERE workoutTemplateId = ? AND scheduleYear = ? AND scheduleMonth = ? AND scheduleDay = ? AND isComplete = 1`,
      [templateId, day.year, day.month, day.day],
    );
  }

  /** Trims, and stores an empty note as none. */
  setSessionNote(sessionId: string, note: string): void {
    this.db.run('UPDATE WorkoutSession SET sessionNote = ? WHERE id = ?', [note.trim() || null, sessionId]);
  }
}

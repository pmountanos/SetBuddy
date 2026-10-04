import { addDays, calendarDate } from '../../domain/calendarDate';
import { type DayPlan, REST, workoutPlan } from '../../domain/schedule';
import { HistoryRepository } from '../historyRepository';
import { ProgramOutlineRepository } from '../outlineRepository';
import { ProgramRepository } from '../programRepository';
import { prepareDatabase } from '../schema';
import { WorkoutSessionRepository } from '../sessionRepository';
import { openTestDb, testEnv } from './testDb';

function setUp() {
  const db = openTestDb();
  prepareDatabase(db);
  const env = testEnv();
  return {
    db,
    env,
    programs: new ProgramRepository(db, env),
    outlines: new ProgramOutlineRepository(db, env),
    sessions: new WorkoutSessionRepository(db, env),
    history: new HistoryRepository(db),
  };
}

describe('schedule cascade', () => {
  const start = calendarDate(2026, 1, 1);

  function scheduleFixture(...days: ('a' | 'b' | 'c' | 'rest')[]) {
    const t = setUp();
    t.programs.createFirstProgram('Test');
    const ids = { a: t.programs.addWorkout('A').id, b: t.programs.addWorkout('B').id, c: t.programs.addWorkout('C').id };
    const plan = (d: 'a' | 'b' | 'c' | 'rest'): DayPlan => (d === 'rest' ? REST : workoutPlan(ids[d]));
    days.forEach((d, offset) => t.programs.setScheduleDay(addDays(start, offset), plan(d)));
    const read = (count: number) => {
      const schedule = t.programs.calendarSchedule(t.programs.activeProgram()!.id);
      return Array.from({ length: count }, (_, offset) => {
        const p = schedule.plan(addDays(start, offset));
        if (!p || p.type === 'rest') return 'rest';
        return (Object.keys(ids) as ('a' | 'b' | 'c')[]).find((k) => ids[k] === p.workoutId);
      });
    };
    return { ...t, plan, read };
  }

  it('rotates only up to the recurrence when pulling an upcoming workout forward', () => {
    const t = scheduleFixture('a', 'b', 'c', 'a', 'b', 'c');
    t.programs.setScheduleDayShiftingFollowing(start, t.plan('c'));
    // C moves to day 0, A and B slide back one; everything after the old C slot is untouched.
    expect(t.read(7)).toEqual(['c', 'a', 'b', 'a', 'b', 'c', 'rest']);
  });

  it('inserts and shifts everything when the value is not coming up soon', () => {
    const t = scheduleFixture('a', 'b', 'a', 'b');
    t.programs.setScheduleDayShiftingFollowing(start, t.plan('c'));
    expect(t.read(6)).toEqual(['c', 'a', 'b', 'a', 'b', 'rest']);
  });

  it('does nothing when the day already has that value', () => {
    const t = scheduleFixture('a', 'b', 'c', 'a');
    t.programs.setScheduleDayShiftingFollowing(start, t.plan('a'));
    expect(t.read(5)).toEqual(['a', 'b', 'c', 'a', 'rest']);
  });

  it('"add a rest day" always inserts, even when rest is already coming up', () => {
    const t = scheduleFixture('a', 'rest', 'b');
    t.programs.insertRestDayShiftingFollowing(start);
    expect(t.read(5)).toEqual(['rest', 'a', 'rest', 'b', 'rest']);
  });

  it('"add a rest day" on a rest day still pushes the schedule', () => {
    const t = scheduleFixture('rest', 'a', 'b');
    t.programs.insertRestDayShiftingFollowing(start);
    expect(t.read(5)).toEqual(['rest', 'rest', 'a', 'b', 'rest']);
  });

  it('turns a deleted workout\'s scheduled days into rest days', () => {
    const t = scheduleFixture('a', 'b', 'a');
    const a = t.plan('a');
    t.programs.deleteWorkout(a.type === 'workout' ? a.workoutId : '');
    expect(t.read(3)).toEqual(['rest', 'b', 'rest']);
  });
});

describe('program editing', () => {
  it('creates a starter program with a full forward schedule of rest days', () => {
    const t = setUp();
    t.programs.createFirstProgram('  ');
    const outline = t.outlines.activeProgramOutline()!;
    expect(outline.programName).toBe('My program');
    expect(outline.workouts.map((w) => w.name)).toEqual(['Workout 1']);
    expect(outline.workouts[0].exercises).toMatchObject([{ name: 'Exercise 1', setCount: 4, kind: 'strength', repsArePerSide: false }]);
    expect(t.outlines.upcomingScheduleRows(500)).toHaveLength(196);
    expect(t.outlines.upcomingScheduleRows(3).every((row) => row.isRestDay)).toBe(true);
    expect(() => t.programs.createFirstProgram('Again')).toThrow();
  });

  it('keeps append order for workouts added in-app, not naming-heuristic order', () => {
    const t = setUp();
    t.programs.createFirstProgram('Test');
    t.programs.addWorkout('Cardio 1');
    t.programs.addWorkout('Push 1');
    expect(t.outlines.activeProgramOutline()!.workouts.map((w) => w.name)).toEqual(['Workout 1', 'Cardio 1', 'Push 1']);
  });

  it('resets the set count to one when an exercise becomes cardio', () => {
    const t = setUp();
    t.programs.createFirstProgram('Test');
    const exercise = t.outlines.activeProgramOutline()!.workouts[0].exercises[0];
    t.programs.setExerciseKind(exercise.id, 'cardio');
    expect(t.outlines.activeProgramOutline()!.workouts[0].exercises[0]).toMatchObject({ kind: 'cardio', setCount: 1 });
    t.programs.setExerciseKind(exercise.id, 'strength');
    expect(t.outlines.activeProgramOutline()!.workouts[0].exercises[0]).toMatchObject({ kind: 'strength', setCount: 1 });
  });

  it('edits, reorders and removes exercises', () => {
    const t = setUp();
    t.programs.createFirstProgram('Test');
    const workout = t.outlines.activeProgramOutline()!.workouts[0];
    const first = workout.exercises[0].id;
    const second = t.programs.addExercise(workout.id, 'Row');
    t.programs.setExerciseName(first, '  Bench  ');
    t.programs.setExerciseName(first, '   ');
    t.programs.setExerciseSetCount(first, 99);
    t.programs.setExerciseRepsPerSide(first, true);
    t.programs.setExerciseNote(first, '  slow  ');
    t.programs.setExerciseNote(second, '   ');
    t.programs.reorderExercises([second, first]);
    expect(t.programs.exercises(workout.id)).toMatchObject([
      { id: second, name: 'Row', note: null, setCount: 4 },
      { id: first, name: 'Bench', note: 'slow', setCount: 20, repsArePerSide: true },
    ]);
    t.programs.deleteExercise(second);
    expect(t.programs.exercises(workout.id)).toHaveLength(1);
  });

  it('starting over keeps completed history readable and clears in-progress sessions', () => {
    const t = setUp();
    t.programs.createFirstProgram('Old');
    const workout = t.outlines.activeProgramOutline()!.workouts[0];
    const exerciseId = workout.exercises[0].id;
    const done = t.sessions.getOrCreateActiveSession(workout.id, calendarDate(2026, 1, 1));
    t.sessions.updateLoggedSet(done.id, exerciseId, 0, 100, 5);
    t.sessions.completeSession(done.id, workout.name);
    t.db.run('UPDATE WorkoutSession SET workoutTitleSnapshot = NULL');
    t.sessions.getOrCreateActiveSession(workout.id, calendarDate(2026, 1, 2));

    t.programs.startOverFreshProgram('New');

    expect(t.outlines.activeProgramOutline()!.programName).toBe('New');
    expect(t.history.completedRows()).toMatchObject([{ title: 'Workout 1', totalVolume: 500 }]);
    expect(t.db.first<{ n: number }>('SELECT count(*) AS n FROM WorkoutSession')!.n).toBe(1);
  });
});

describe('logging a session', () => {
  function started() {
    const t = setUp();
    t.programs.createFirstProgram('Test');
    const workout = t.outlines.activeProgramOutline()!.workouts[0];
    const day = calendarDate(2026, 1, 1);
    return { ...t, workout, exerciseId: workout.exercises[0].id, day };
  }

  it('creates one row per template set and resumes the same session', () => {
    const t = started();
    const session = t.sessions.getOrCreateActiveSession(t.workout.id, t.day);
    expect(t.sessions.loggedSets(session.id)).toHaveLength(4);
    expect(t.sessions.getOrCreateActiveSession(t.workout.id, t.day).id).toBe(session.id);
    expect(t.sessions.activeSession(t.workout.id, t.day)?.id).toBe(session.id);
    expect(t.sessions.hasCompletedSession(t.workout.id, t.day)).toBe(false);
  });

  it('follows a set-count change made mid-session', () => {
    const t = started();
    const session = t.sessions.getOrCreateActiveSession(t.workout.id, t.day);
    t.programs.setExerciseSetCount(t.exerciseId, 2);
    t.sessions.getOrCreateActiveSession(t.workout.id, t.day);
    expect(t.sessions.loggedSets(session.id).map((s) => s.setIndex)).toEqual([0, 1]);
  });

  it('saves only entered sets on finish, and offers them as the next reference', () => {
    const t = started();
    const session = t.sessions.getOrCreateActiveSession(t.workout.id, t.day);
    t.sessions.updateLoggedSet(session.id, t.exerciseId, 0, 100, 5);
    t.sessions.updateLoggedSet(session.id, t.exerciseId, 1, 102.5, 4);
    t.sessions.setSessionNote(session.id, '  good day ');
    t.sessions.completeSession(session.id, t.workout.name);

    expect(t.sessions.hasCompletedSession(t.workout.id, t.day)).toBe(true);
    expect(t.sessions.activeSession(t.workout.id, t.day)).toBeNull();
    const detail = t.history.sessionDetail(session.id)!;
    expect(detail.sessionNote).toBe('good day');
    expect(detail.exercises[0].sets.map((s) => [s.setNumber, s.weight, s.reps])).toEqual([
      [1, 100, 5],
      [2, 102.5, 4],
    ]);
    expect(detail.totalVolume).toBe(100 * 5 + 102.5 * 4);
    expect(t.history.completedRows()).toMatchObject([{ title: 'Workout 1', totalVolume: 910, hasSessionNote: true }]);

    const reference = t.sessions.mostRecentLoggedValuesByExercise().get(t.exerciseId)!;
    expect(reference.get(0)).toMatchObject({ weight: 100, reps: 5 });
    expect(reference.has(2)).toBe(false);
  });

  it('uses the most recent completed session as the reference', () => {
    const t = started();
    for (const [offset, weight] of [[0, 100], [1, 110]] as const) {
      const session = t.sessions.getOrCreateActiveSession(t.workout.id, addDays(t.day, offset));
      t.sessions.updateLoggedSet(session.id, t.exerciseId, 0, weight, 5);
      t.sessions.completeSession(session.id, t.workout.name);
    }
    expect(t.sessions.mostRecentLoggedValuesByExercise().get(t.exerciseId)!.get(0)!.weight).toBe(110);
  });

  it('reopens a finished session with its entered sets intact', () => {
    const t = started();
    const session = t.sessions.getOrCreateActiveSession(t.workout.id, t.day);
    t.sessions.updateLoggedSet(session.id, t.exerciseId, 0, 100, 5);
    t.sessions.completeSession(session.id, t.workout.name);

    t.sessions.reopenCompletedSession(t.workout.id, t.day);

    const reopened = t.sessions.getOrCreateActiveSession(t.workout.id, t.day);
    expect(reopened.id).toBe(session.id);
    expect(t.history.completedRows()).toEqual([]);
    const sets = t.sessions.loggedSets(session.id);
    expect(sets).toHaveLength(4);
    expect(sets.find((s) => s.setIndex === 0)).toMatchObject({ weight: 100, reps: 5, userEditedValues: true });
  });

  it('logs cardio as minutes and max heart rate, outside volume', () => {
    const t = started();
    t.programs.setExerciseKind(t.exerciseId, 'cardio');
    const session = t.sessions.getOrCreateActiveSession(t.workout.id, t.day);
    t.sessions.updateCardioLoggedSet(session.id, t.exerciseId, 0, 22.5, 161);
    t.sessions.completeSession(session.id, t.workout.name);

    expect(t.history.sessionDetail(session.id)!.exercises[0]).toMatchObject({
      kind: 'cardio',
      cardioMinutes: 22.5,
      volume: 0,
      sets: [{ cardioMinutes: 22.5, maxHeartRate: 161, volume: 0 }],
    });
    expect(t.history.completedRows()[0].totalVolume).toBe(0);
    expect(t.sessions.mostRecentLoggedValuesByExercise().get(t.exerciseId)!.get(0)).toMatchObject({ cardioMinutes: 22.5, maxHeartRate: 161 });
  });
});

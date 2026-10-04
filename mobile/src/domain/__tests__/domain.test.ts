import { addDays, calendarDate, calendarDateOf, compareDates, isoDate } from '../calendarDate';
import { FUZZY_THRESHOLD, matchCarryover, refKey } from '../carryoverMatcher';
import { exerciseKindFromRaw } from '../exerciseKind';
import { ProgramCalendarSchedule, REST, sameDayPlan, todayScheduleStatus, workoutPlan } from '../schedule';
import { similarityRatio } from '../stringSimilarity';
import { setVolume, totalVolume } from '../volume';
import { compareWorkoutNames, compareWorkouts } from '../workoutDisplaySort';

describe('CalendarDate', () => {
  it('adds days across month, year and leap-day boundaries', () => {
    expect(addDays(calendarDate(2026, 1, 31), 1)).toEqual(calendarDate(2026, 2, 1));
    expect(addDays(calendarDate(2026, 12, 31), 1)).toEqual(calendarDate(2027, 1, 1));
    expect(addDays(calendarDate(2028, 2, 28), 1)).toEqual(calendarDate(2028, 2, 29));
    expect(addDays(calendarDate(2026, 3, 1), -1)).toEqual(calendarDate(2026, 2, 28));
    expect(addDays(calendarDate(2026, 10, 4), 196)).toEqual(calendarDate(2027, 4, 18));
  });

  it('orders and formats dates', () => {
    expect(compareDates(calendarDate(2026, 10, 4), calendarDate(2026, 9, 30))).toBeGreaterThan(0);
    expect(compareDates(calendarDate(2026, 10, 4), calendarDate(2026, 10, 4))).toBe(0);
    expect(isoDate(calendarDate(2026, 3, 7))).toBe('2026-03-07');
    expect(calendarDateOf(new Date(2026, 9, 4, 23, 59))).toEqual(calendarDate(2026, 10, 4));
  });
});

describe('volume', () => {
  it('totals sets', () => {
    expect(
      totalVolume([
        { weight: 100, reps: 5, repsArePerSide: false },
        { weight: 50, reps: 10, repsArePerSide: false },
      ]),
    ).toBe(100 * 5 + 50 * 10);
  });
  it('treats negative weight and zero reps as no work', () => {
    expect(setVolume(-50, 10)).toBe(0);
    expect(setVolume(200, 0)).toBe(0);
  });
  it('doubles per-side work', () => {
    expect(setVolume(50, 10, false)).toBe(500);
    expect(setVolume(50, 10, true)).toBe(1000);
  });
});

describe('todayScheduleStatus', () => {
  const today = calendarDate(2025, 1, 18);
  it('reports a day outside the schedule', () => {
    expect(todayScheduleStatus(today, new ProgramCalendarSchedule(), new Map())).toEqual({ type: 'dayNotScheduled' });
  });
  it('reports workout and rest days', () => {
    const schedule = new ProgramCalendarSchedule();
    schedule.set(today, workoutPlan('w1'));
    expect(todayScheduleStatus(today, schedule, new Map([['w1', 'Push']]))).toEqual({ type: 'workoutDay', workoutId: 'w1', title: 'Push' });
    expect(todayScheduleStatus(today, schedule, new Map())).toMatchObject({ title: 'Workout' });
    schedule.set(today, REST);
    expect(todayScheduleStatus(today, schedule, new Map())).toEqual({ type: 'restDay' });
  });
  it('compares day plans by value', () => {
    expect(sameDayPlan(workoutPlan('a'), workoutPlan('a'))).toBe(true);
    expect(sameDayPlan(workoutPlan('a'), workoutPlan('b'))).toBe(false);
    expect(sameDayPlan(REST, { type: 'rest' })).toBe(true);
    expect(sameDayPlan(REST, workoutPlan('a'))).toBe(false);
  });
});

describe('workout display sort', () => {
  it('orders the Push/Pull/Legs cycle by name', () => {
    const names = ['Legs 2', 'Push 1', 'Pull 2', 'Pull 1', 'Push 2', 'Legs 1', 'ZZ Other'];
    expect([...names].sort(compareWorkoutNames)).toEqual(['Push 1', 'Pull 1', 'Legs 1', 'Push 2', 'Pull 2', 'Legs 2', 'ZZ Other']);
  });
  it('puts sortOrder ahead of the naming heuristic', () => {
    const workouts = [
      { name: 'Pull 1', sortOrder: 2 },
      { name: 'Cardio 1', sortOrder: 1 },
      { name: 'Push 1', sortOrder: 0 },
    ];
    expect(workouts.sort(compareWorkouts).map((w) => w.name)).toEqual(['Push 1', 'Cardio 1', 'Pull 1']);
  });
});

describe('string similarity', () => {
  it('scores identical strings as one', () => expect(similarityRatio('bench press', 'bench press')).toBe(1));
  it('scores unrelated strings low', () => expect(similarityRatio('bench press', 'squat')).toBeLessThan(0.3));
  it('scores a one-letter typo above the fuzzy threshold', () =>
    expect(similarityRatio('bench press', 'bench pres')).toBeGreaterThanOrEqual(FUZZY_THRESHOLD));
});

describe('matchCarryover', () => {
  const day = (sheetName: string, ...names: string[]) => ({ sheetName, isRestDay: false, exercises: names.map((name) => ({ name })) });

  it('auto-matches exact names, ignoring case and surrounding whitespace', () => {
    const result = matchCarryover([{ id: 'old', name: 'Bench Press' }], [day('Push 1', '  bench press  ')]);
    expect(result.autoCarryover.get(refKey({ workoutSheetName: 'Push 1', exerciseName: '  bench press  ' }))).toBe('old');
    expect(result.suggestions).toEqual([]);
  });

  it('suggests close non-exact matches', () => {
    const result = matchCarryover([{ id: 'old', name: 'Bench Press' }], [day('Push 1', 'Bench Pres')]);
    expect(result.autoCarryover.size).toBe(0);
    expect(result.suggestions).toEqual([
      { newExercise: { workoutSheetName: 'Push 1', exerciseName: 'Bench Pres' }, oldExerciseId: 'old', oldExerciseName: 'Bench Press' },
    ]);
  });

  it('ignores unrelated names', () => {
    const result = matchCarryover([{ id: 'old', name: 'Bench Press' }], [day('Legs 1', 'Back Squat')]);
    expect(result.autoCarryover.size).toBe(0);
    expect(result.suggestions).toEqual([]);
  });

  it('assigns the best pairs without claiming an old exercise twice', () => {
    const result = matchCarryover(
      [
        { id: 'bench', name: 'Bench Press' },
        { id: 'machine', name: 'Bench Press Machine' },
      ],
      [day('Push 1', 'Bench Pres', 'Bench Press Machin')],
    );
    expect(result.suggestions.map((s) => [s.newExercise.exerciseName, s.oldExerciseId])).toEqual([
      ['Bench Pres', 'bench'],
      ['Bench Press Machin', 'machine'],
    ]);
  });

  it('copes with a sheet that repeats an exercise name', () => {
    const result = matchCarryover([{ id: 'old', name: 'Hip adduction' }], [day('Legs 1', 'Hip adduction', 'Squat', 'Hip adduction')]);
    expect(result.autoCarryover.size).toBe(1);
  });
});

describe('exerciseKindFromRaw', () => {
  it('reads unknown values as strength', () => {
    expect(exerciseKindFromRaw('cardio')).toBe('cardio');
    expect(exerciseKindFromRaw(null)).toBe('strength');
    expect(exerciseKindFromRaw('something else')).toBe('strength');
  });
});

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { openTestDb, testEnv } from '../../data/__tests__/testDb';
import { HistoryRepository } from '../../data/historyRepository';
import { ProgramOutlineRepository } from '../../data/outlineRepository';
import { importProgramReplacingStore } from '../../data/programImporter';
import { ProgramRepository } from '../../data/programRepository';
import { prepareDatabase } from '../../data/schema';
import { WorkoutSessionRepository } from '../../data/sessionRepository';
import { calendarDate } from '../../domain/calendarDate';
import { matchCarryover } from '../../domain/carryoverMatcher';
import { decodeXmlEntities, parseXml } from '../miniSax';
import { cardioSectionHeaderRow, exercisesFromSheet, marksRepsPerSide, parseSheetCells, ProgramImportError } from '../programXlsxParser';
import { parseProgramXlsx } from '../readWorkbook';

/** The same real workbooks the native iOS and Android tests use. */
const fixture = (name: string) => new Uint8Array(readFileSync(join(__dirname, '../../../../Set BuddyTests/Fixtures', name)));
const cells = (entries: Record<string, string>) => new Map(Object.entries(entries));

function setUp() {
  const db = openTestDb();
  prepareDatabase(db);
  const env = testEnv();
  return { db, env, programs: new ProgramRepository(db, env), outlines: new ProgramOutlineRepository(db, env) };
}

describe('miniSax', () => {
  it('reports elements, attributes and text in order, dropping element namespace prefixes', () => {
    const events: string[] = [];
    parseXml(`<?xml version="1.0"?><x:a r:id="1" n='two &amp; "three"'><b/>t&lt;1<![CDATA[<raw>]]></x:a>`, {
      start: (name, attributes) => events.push(`+${name} ${JSON.stringify(attributes)}`),
      text: (text) => events.push(`"${text}"`),
      end: (name) => events.push(`-${name}`),
    });
    expect(events).toEqual(['+a {"r:id":"1","n":"two & \\"three\\""}', '+b {}', '-b', '"t<1"', '"<raw>"', '-a']);
  });

  it('decodes numeric entities', () => {
    expect(decodeXmlEntities('&#215; &#xD7; &unknown;')).toBe('× × &unknown;');
  });
});

describe('sheet parsing', () => {
  it('reads shared, inline, boolean and numeric cells', () => {
    const xml = `<worksheet><sheetData><row r="1">
      <c r="A1" t="s"><v>1</v></c><c r="B1" t="inlineStr"><is><t>Inline</t></is></c>
      <c r="C1" t="b"><v>1</v></c><c r="D1"><v>42</v></c><c r="E1"/></row></sheetData></worksheet>`;
    expect(Object.fromEntries(parseSheetCells(xml, ['zero', 'Bench Press']))).toEqual({ A1: 'Bench Press', B1: 'Inline', C1: 'TRUE', D1: '42' });
  });

  it('recognises per-side markers by exact match only', () => {
    expect(['x', ' X ', '✓', 'yes', 'TRUE', '1'].every(marksRepsPerSide)).toBe(true);
    expect(['', undefined, 'no', 'xx', '2'].some(marksRepsPerSide)).toBe(false);
  });

  it('uses the legacy columns when there are no headers (B = note, C = per side)', () => {
    expect(exercisesFromSheet(cells({ A1: 'Squat', B1: 'Deep', C1: 'x', A2: 'Lunge' }))).toEqual([
      { name: 'Squat', note: 'Deep', repsArePerSide: true, kind: 'strength' },
      { name: 'Lunge', note: null, repsArePerSide: false, kind: 'strength' },
    ]);
  });

  it('stops strength rows at the cardio section header', () => {
    const sheet = cells({
      A1: 'Excercise_Name', B1: 'Per side', C1: 'Notes',
      A2: 'Bench Press', B2: 'x',
      A3: 'Barbell Row',
      B4: 'Minutes', C4: 'Peak HR',
      A5: 'Cardio',
    });
    expect(cardioSectionHeaderRow(sheet)).toBe(4);
    expect(exercisesFromSheet(sheet).map((e) => [e.name, e.kind, e.repsArePerSide])).toEqual([
      ['Bench Press', 'strength', true],
      ['Barbell Row', 'strength', false],
      ['Cardio', 'cardio', false],
    ]);
  });

  it('rejects a file that is not a workbook', () => {
    expect(() => parseProgramXlsx(new Uint8Array([1, 2, 3]))).toThrow(ProgramImportError);
  });
});

describe('Set Buddy-4.xlsx', () => {
  const cycle = parseProgramXlsx(fixture('Set Buddy-4.xlsx'));

  it('parses cardio sections and whole cardio days', () => {
    // "Push 1": 8 strength exercises, then a trailing "Cardio" set.
    const push1 = cycle.find((day) => day.sheetName === 'Push 1')!;
    expect(push1.isRestDay).toBe(false);
    expect(push1.exercises).toHaveLength(9);
    expect(push1.exercises.slice(0, -1).every((e) => e.kind === 'strength')).toBe(true);
    expect(push1.exercises.at(-1)).toMatchObject({ name: 'Cardio', kind: 'cardio' });

    // "Cardio 1": a whole cardio day — not a rest day despite having no strength rows.
    const cardio1 = cycle.find((day) => day.sheetName === 'Cardio 1')!;
    expect(cardio1.isRestDay).toBe(false);
    expect(cardio1.exercises).toMatchObject([{ name: 'Cardio', kind: 'cardio' }]);

    // "Rest 1": genuinely empty, still a rest day.
    expect(cycle.find((day) => day.sheetName === 'Rest 1')!.isRestDay).toBe(true);
  });

  it('imports in spreadsheet cycle order, with one set for cardio', () => {
    const t = setUp();
    importProgramReplacingStore(t.db, t.env, cycle, { programName: 'Cardio Import', startDate: calendarDate(2026, 1, 1), horizonDays: 12 });

    const outline = t.outlines.activeProgramOutline()!;
    expect(outline.workouts.map((w) => w.name)).toEqual([
      'Push 1', 'Cardio 1', 'Pull 1', 'Cardio 2', 'Legs 1',
      'Push 2', 'Cardio 3', 'Pull 2', 'Cardio 4', 'Legs 2',
    ]);
    const push1 = outline.workouts[0].exercises;
    expect(push1.slice(0, -1).every((e) => e.kind === 'strength' && e.setCount === 4)).toBe(true);
    expect(push1.at(-1)).toMatchObject({ kind: 'cardio', setCount: 1 });
    expect(outline.workouts[1].exercises.every((e) => e.kind === 'cardio' && e.setCount === 1)).toBe(true);

    // The schedule follows the workbook's tab order from the start date.
    const titles = t.outlines.upcomingScheduleRows(12).map((row) => row.workoutTitle ?? 'Rest');
    expect(titles).toEqual(cycle.slice(0, 12).map((day) => (day.isRestDay ? 'Rest' : day.sheetName)));
  });

  it('can start the cycle part-way through the workbook', () => {
    const t = setUp();
    importProgramReplacingStore(t.db, t.env, cycle, { programName: 'Offset', startDate: calendarDate(2026, 1, 1), cycleStartIndex: 2, horizonDays: 3 });
    expect(t.outlines.upcomingScheduleRows(1)[0].workoutTitle ?? 'Rest').toBe(cycle[2].isRestDay ? 'Rest' : cycle[2].sheetName);
  });

  it('re-imports over itself with carry-over, keeping exercise ids and history', () => {
    const t = setUp();
    const options = { programName: 'First', startDate: calendarDate(2026, 1, 1) };
    importProgramReplacingStore(t.db, t.env, cycle, options);
    const before = t.outlines.activeProgramOutline()!;
    const bench = before.workouts[0].exercises[0];
    const sessions = new WorkoutSessionRepository(t.db, t.env);
    const done = sessions.getOrCreateActiveSession(before.workouts[0].id, calendarDate(2026, 1, 1));
    sessions.updateLoggedSet(done.id, bench.id, 0, 80, 8);
    sessions.completeSession(done.id, before.workouts[0].name);
    sessions.getOrCreateActiveSession(before.workouts[2].id, calendarDate(2026, 1, 3));

    // The workbook lists one exercise twice on a sheet; both rows resolve to the same old id.
    const match = matchCarryover(t.programs.existingExercisesForCarryover(), cycle);
    expect(match.suggestions).toEqual([]);
    importProgramReplacingStore(t.db, t.env, cycle, { ...options, programName: 'Second', exerciseCarryover: match.autoCarryover });

    const after = t.outlines.activeProgramOutline()!;
    expect(after.programName).toBe('Second');
    expect(after.workouts.flatMap((w) => w.exercises)).toHaveLength(before.workouts.flatMap((w) => w.exercises).length);
    expect(after.workouts[0].exercises[0].id).toBe(bench.id);
    expect(sessions.mostRecentLoggedValuesByExercise().get(bench.id)!.get(0)).toMatchObject({ weight: 80, reps: 8 });
    // Completed history survives the replacement; the in-progress session does not.
    expect(new HistoryRepository(t.db).completedRows()).toMatchObject([{ title: 'Push 1', totalVolume: bench.repsArePerSide ? 1280 : 640 }]);
    expect(t.db.first<{ n: number }>('SELECT count(*) AS n FROM WorkoutSession')!.n).toBe(1);
  });

  it('leaves the existing program in place when an import fails', () => {
    const t = setUp();
    t.programs.createFirstProgram('Keep me');
    expect(() => importProgramReplacingStore(t.db, t.env, [], { programName: 'Empty', startDate: calendarDate(2026, 1, 1) })).toThrow(ProgramImportError);
    const broken = [{ sheetName: 'A', isRestDay: false, exercises: [{ name: null as unknown as string }] }];
    expect(() => importProgramReplacingStore(t.db, t.env, broken, { programName: 'Broken', startDate: calendarDate(2026, 1, 1) })).toThrow();
    expect(t.outlines.activeProgramOutline()!.programName).toBe('Keep me');
  });
});

describe('Set Buddy-2.xlsx', () => {
  it('parses the earlier strength-only workbook', () => {
    const cycle = parseProgramXlsx(fixture('Set Buddy-2.xlsx'));
    expect(cycle.length).toBeGreaterThan(0);
    const workouts = cycle.filter((day) => !day.isRestDay);
    expect(workouts.length).toBeGreaterThan(0);
    expect(workouts.every((day) => day.exercises.every((e) => e.kind === 'strength' && e.name.length > 0))).toBe(true);
  });
});

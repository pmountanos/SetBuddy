import { strFromU8, unzipSync } from 'fflate';

import { openTestDb, testEnv } from '../../data/__tests__/testDb';
import { HistoryRepository } from '../../data/historyRepository';
import { ProgramOutlineRepository } from '../../data/outlineRepository';
import { ProgramRepository } from '../../data/programRepository';
import { prepareDatabase } from '../../data/schema';
import { WorkoutSessionRepository } from '../../data/sessionRepository';
import { calendarDate } from '../../domain/calendarDate';
import { workoutPlan } from '../../domain/schedule';
import { parseSheetCells } from '../../xlsx/programXlsxParser';
import { parseProgramXlsx } from '../../xlsx/readWorkbook';
import { historyCsv, historyXlsx, localTimestamp } from '../historyExport';
import { programCsv, programXlsx } from '../programExport';
import { columnLetters, csvEscape, ExportError, uniqueSheetName } from '../spreadsheet';

const text = (bytes: Uint8Array) => strFromU8(bytes);

function programWithHistory() {
  const db = openTestDb();
  prepareDatabase(db);
  const env = testEnv();
  const programs = new ProgramRepository(db, env);
  const outlines = new ProgramOutlineRepository(db, env);
  const sessions = new WorkoutSessionRepository(db, env);
  programs.createFirstProgram('My "big" program');
  const workout = outlines.activeProgramOutline()!.workouts[0];
  const bench = workout.exercises[0].id;
  programs.setExerciseName(bench, 'Bench, flat');
  programs.setExerciseNote(bench, 'Pause <1s> & drive');
  programs.setExerciseRepsPerSide(bench, true);
  const run = programs.addExercise(workout.id, 'Treadmill');
  programs.setExerciseKind(run, 'cardio');
  programs.setScheduleDay(calendarDate(2026, 1, 1), workoutPlan(workout.id));

  const session = sessions.getOrCreateActiveSession(workout.id, calendarDate(2026, 1, 1));
  sessions.updateLoggedSet(session.id, bench, 0, 40, 10);
  sessions.updateCardioLoggedSet(session.id, run, 0, 22.5, 161);
  sessions.setSessionNote(session.id, 'Felt good, strong');
  sessions.completeSession(session.id, workout.name);
  return { programs, outlines, history: new HistoryRepository(db), env };
}

describe('spreadsheet helpers', () => {
  it('names columns like Excel', () => {
    expect([0, 25, 26, 27, 701, 702].map(columnLetters)).toEqual(['A', 'Z', 'AA', 'AB', 'ZZ', 'AAA']);
  });
  it('quotes CSV fields only when needed', () => {
    expect(csvEscape('plain')).toBe('plain');
    expect(csvEscape('a,b')).toBe('"a,b"');
    expect(csvEscape('say "hi"')).toBe('"say ""hi"""');
  });
  it('makes sheet names legal and unique', () => {
    const used = new Set<string>();
    expect(uniqueSheetName('Push/Pull [1]', used)).toBe('PushPull 1');
    expect(uniqueSheetName('PushPull 1', used)).toBe('PushPull 1 (2)');
    expect(uniqueSheetName('   ', used)).toBe('Workout');
    expect(uniqueSheetName('x'.repeat(40), used)).toHaveLength(31);
    expect(uniqueSheetName('x'.repeat(40), used)).toBe(`${'x'.repeat(27)} (2)`);
  });
});

describe('program export', () => {
  it('writes a workbook the importer reads back unchanged, cardio included', () => {
    const t = programWithHistory();
    const cycle = parseProgramXlsx(programXlsx(t.outlines.activeProgramOutline()!));
    expect(cycle).toEqual([
      {
        sheetName: 'Workout 1',
        isRestDay: false,
        exercises: [
          { name: 'Bench, flat', note: 'Pause <1s> & drive', repsArePerSide: true, kind: 'strength' },
          { name: 'Treadmill', note: null, repsArePerSide: false, kind: 'cardio' },
        ],
      },
    ]);
  });

  it('refuses to export when there are no workouts', () => {
    expect(() => programXlsx({ programId: 'p', programName: 'Empty', workouts: [] })).toThrow(ExportError);
  });

  it('writes the program and schedule as CSV', () => {
    const t = programWithHistory();
    const program = t.programs.activeProgram()!;
    const lines = text(programCsv(t.outlines.activeProgramOutline()!, t.programs.calendarSchedule(program.id))).split('\n');
    expect(lines[0]).toBe('﻿kind,program_name,,,'.replace('﻿', lines[0].startsWith('﻿') ? '﻿' : ''));
    expect(lines.slice(1, 6)).toEqual([
      'program,"My ""big"" program",,,',
      'workout,Workout 1,,,',
      'column,sort_order,exercise_name,set_count,note,per_side,type',
      'exercise,0,"Bench, flat",4,Pause <1s> & drive,yes,strength',
      'exercise,1,Treadmill,1,,no,cardio',
    ]);
    expect(lines).toContain('schedule,2026-01-01,workout,Workout 1,');
    expect(lines).toContain('schedule,2026-01-02,rest,,');
  });
});

describe('history export', () => {
  it('writes one row per set and a workout_total row per session', () => {
    const t = programWithHistory();
    const sessions = t.history.allCompletedSessionDetails();
    const stamp = localTimestamp(sessions[0].completedAt);
    const lines = text(historyCsv(sessions)).replace('﻿', '').split('\n');
    expect(lines).toEqual([
      'completed_at,workout,schedule_day,total_volume,exercise,set_number,weight_kg,reps,per_side,set_volume,session_note,type,cardio_minutes,max_heart_rate',
      `${stamp},Workout 1,2026-01-01,800,"Bench, flat",1,40,10,yes,800,"Felt good, strong",strength,0,0`,
      `${stamp},Workout 1,2026-01-01,800,Treadmill,1,0,0,no,0,"Felt good, strong",cardio,22.5,161`,
      `${stamp},Workout 1,2026-01-01,800,workout_total,,,,,800,"Felt good, strong",,,`,
    ]);

    const sheet = strFromU8(unzipSync(historyXlsx(sessions))['xl/worksheets/sheet1.xml']);
    const cells = parseSheetCells(sheet, []);
    expect(cells.get('E2')).toBe('Bench, flat');
    expect(cells.get('J2')).toBe('800');
    expect(cells.get('M3')).toBe('22.5');
    expect(cells.get('E4')).toBe('workout_total');
  });

  it('still produces a valid workbook with no history', () => {
    const files = unzipSync(historyXlsx([]));
    expect(Object.keys(files).sort()).toEqual(['[Content_Types].xml', '_rels/.rels', 'xl/_rels/workbook.xml.rels', 'xl/workbook.xml', 'xl/worksheets/sheet1.xml']);
    expect(text(historyCsv([])).split('\n')).toHaveLength(1);
  });
});

import type { ProgramOutline } from '../data/outlineRepository';
import { isoDate } from '../domain/calendarDate';
import type { ProgramCalendarSchedule } from '../domain/schedule';
import { type Cell, csvBytes, csvEscape, ExportError, makeWorkbook, uniqueSheetName } from './spreadsheet';

const NO_PROGRAM = 'There is no program to export. Create or import one on the Program tab.';

/**
 * One sheet per workout in display order, in the layout the importer reads back (name, notes, per-side marker),
 * plus a **Type** column.
 */
export function programXlsx(outline: ProgramOutline): Uint8Array {
  if (outline.workouts.length === 0) throw new ExportError(NO_PROGRAM);
  const used = new Set<string>();
  return makeWorkbook(
    outline.workouts.map((workout) => {
      const rows: Cell[][] = [['Exercise_Name', 'Notes', 'Per side', 'Type']];
      for (const exercise of workout.exercises) {
        rows.push([exercise.name, exercise.note ?? '', exercise.repsArePerSide ? 'x' : '', exercise.kind]);
      }
      if (workout.exercises.length === 0) rows.push(['', '', '', '']);
      return { name: uniqueSheetName(workout.name, used), rows };
    }),
  );
}

/** Human-readable program (set counts, notes, per-side, type) followed by the schedule as ISO-dated rows. */
export function programCsv(outline: ProgramOutline, schedule: ProgramCalendarSchedule): Uint8Array {
  const lines = ['kind,program_name,,,', `program,${csvEscape(outline.programName)},,,`];
  for (const workout of outline.workouts) {
    lines.push(`workout,${csvEscape(workout.name)},,,`);
    lines.push('column,sort_order,exercise_name,set_count,note,per_side,type');
    for (const exercise of workout.exercises) {
      lines.push(
        ['exercise', exercise.sortOrder, csvEscape(exercise.name), exercise.setCount, csvEscape(exercise.note ?? ''), exercise.repsArePerSide ? 'yes' : 'no', exercise.kind].join(','),
      );
    }
  }
  lines.push('kind,schedule_date,rest_or_workout,workout_name,');
  const titles = new Map(outline.workouts.map((workout) => [workout.id, workout.name]));
  for (const { date, plan } of schedule.entries) {
    if (plan.type === 'rest') {
      lines.push(`schedule,${isoDate(date)},rest,,`);
    } else {
      const name = titles.get(plan.workoutId);
      lines.push(name === undefined ? `schedule,${isoDate(date)},unknown,,` : `schedule,${isoDate(date)},workout,${csvEscape(name)},`);
    }
  }
  return csvBytes(lines);
}

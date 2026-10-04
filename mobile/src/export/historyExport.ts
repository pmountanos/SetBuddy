import type { HistorySessionDetail } from '../data/historyRepository';
import { isoDate } from '../domain/calendarDate';
import { type Cell, csvBytes, csvEscape, makeWorkbook } from './spreadsheet';

const HEADERS = [
  'completed_at', 'workout', 'schedule_day', 'total_volume', 'exercise',
  'set_number', 'weight_kg', 'reps', 'per_side', 'set_volume', 'session_note',
  'type', 'cardio_minutes', 'max_heart_rate',
];

/** `yyyy-MM-dd HH:mm:ss` in the device's time zone. */
export function localTimestamp(epochMillis: number): string {
  if (!epochMillis) return '';
  const d = new Date(epochMillis);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

/** One row per logged set; each session ends with a `workout_total` row carrying the summed set volume. */
function sessionRows(session: HistorySessionDetail): Cell[][] {
  const lead: Cell[] = [localTimestamp(session.completedAt), session.title, isoDate(session.scheduleDate), session.totalVolume];
  const note = session.sessionNote ?? '';
  const rows: Cell[][] = [];
  for (const exercise of session.exercises) {
    for (const set of exercise.sets) {
      rows.push([
        ...lead, exercise.name, set.setNumber, set.weight, set.reps, set.repsArePerSide ? 'yes' : 'no', set.volume, note,
        set.kind, set.cardioMinutes, set.maxHeartRate,
      ]);
    }
  }
  rows.push([...lead, 'workout_total', '', '', '', '', session.totalVolume, note, '', '', '']);
  return rows;
}

export function historyXlsx(sessions: HistorySessionDetail[]): Uint8Array {
  const rows: Cell[][] = [HEADERS, ...sessions.flatMap(sessionRows)];
  if (sessions.length === 0) rows.push(['', '', '', 0, '', 0, 0, 0, 'no', 0, '', '', 0, 0]);
  return makeWorkbook([{ name: 'History', rows }]);
}

export function historyCsv(sessions: HistorySessionDetail[]): Uint8Array {
  const line = (row: Cell[]) => row.map((cell) => (typeof cell === 'number' ? String(cell) : csvEscape(cell))).join(',');
  return csvBytes([HEADERS.join(','), ...sessions.flatMap(sessionRows).map(line)]);
}

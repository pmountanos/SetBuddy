import { addDays, type CalendarDate, dateKey } from '@/domain/calendarDate';
import { type ProgramCalendarSchedule, todayScheduleStatus } from '@/domain/schedule';

export interface ReminderPrefs {
  enabled: boolean;
  /** 0…23 */
  hour: number;
  /** 0…59 */
  minute: number;
}

export const DEFAULT_REMINDER_PREFS: ReminderPrefs = { enabled: false, hour: 8, minute: 0 };

/** One reminder per calendar day is kept scheduled this many days ahead; reopening the app rolls it forward. */
export const REMINDER_HORIZON_DAYS = 14;

export interface PlannedReminder {
  /** Stable per calendar day (the same scheme the native apps used). */
  id: string;
  fireAt: Date;
  title: string;
  body: string;
}

export function clampReminderPrefs(prefs: ReminderPrefs): ReminderPrefs {
  const clamp = (value: number, max: number) => Math.min(max, Math.max(0, Math.trunc(Number.isFinite(value) ? value : 0)));
  return { enabled: prefs.enabled, hour: clamp(prefs.hour, 23), minute: clamp(prefs.minute, 59) };
}

/**
 * The reminders that should be pending right now: one per day for the next {@link REMINDER_HORIZON_DAYS} days at
 * the chosen time, saying what that day holds, skipping any whose time has already passed. Empty when reminders
 * are off.
 *
 * @param schedule the active program's schedule, or `null` when there is no program.
 */
export function planReminders(input: {
  prefs: ReminderPrefs;
  today: CalendarDate;
  now: Date;
  schedule: ProgramCalendarSchedule | null;
  workoutTitles: ReadonlyMap<string, string>;
  horizonDays?: number;
}): PlannedReminder[] {
  const { today, now, schedule, workoutTitles, horizonDays = REMINDER_HORIZON_DAYS } = input;
  const prefs = clampReminderPrefs(input.prefs);
  if (!prefs.enabled) return [];

  const reminders: PlannedReminder[] = [];
  for (let offset = 0; offset < horizonDays; offset++) {
    const date = addDays(today, offset);
    const fireAt = new Date(date.year, date.month - 1, date.day, prefs.hour, prefs.minute, 0, 0);
    if (fireAt.getTime() <= now.getTime()) continue;
    reminders.push({ id: `net.mountanos.setbuddy.schedule.${dateKey(date)}`, fireAt, ...content(date, schedule, workoutTitles) });
  }
  return reminders;
}

function content(date: CalendarDate, schedule: ProgramCalendarSchedule | null, workoutTitles: ReadonlyMap<string, string>): { title: string; body: string } {
  if (!schedule) return { title: 'Set Buddy', body: 'Set up your training program in the app.' };
  const status = todayScheduleStatus(date, schedule, workoutTitles);
  switch (status.type) {
    case 'restDay':
      return { title: 'Rest day', body: 'Today is a scheduled rest day.' };
    case 'workoutDay':
      return { title: 'Workout day', body: `Today: ${status.title}.` };
    default:
      return { title: 'Set Buddy', body: 'Open the app to see your plan.' };
  }
}

import { type CalendarDate, compareDates, dateKey } from './calendarDate';

/** What the program assigns to a single calendar date; also what a schedule picker can choose. */
export type DayPlan = { type: 'rest' } | { type: 'workout'; workoutId: string };

export const REST: DayPlan = { type: 'rest' };
export const workoutPlan = (workoutId: string): DayPlan => ({ type: 'workout', workoutId });

export function sameDayPlan(a: DayPlan, b: DayPlan): boolean {
  if (a.type === 'workout' && b.type === 'workout') return a.workoutId === b.workoutId;
  return a.type === b.type;
}

/**
 * Program schedule stored as explicit calendar dates (not abstract weekdays).
 * Each key is one calendar day; the value is rest or a specific workout.
 */
export class ProgramCalendarSchedule {
  private readonly days = new Map<string, { date: CalendarDate; plan: DayPlan }>();

  /**
   * How this date is scheduled, if the program defines it.
   * `undefined` means this calendar day is outside defined schedule data (import range, program bounds, etc.).
   */
  plan(date: CalendarDate): DayPlan | undefined {
    return this.days.get(dateKey(date))?.plan;
  }

  set(date: CalendarDate, plan: DayPlan): void {
    this.days.set(dateKey(date), { date, plan });
  }

  /** Every scheduled day, oldest first. */
  get entries(): { date: CalendarDate; plan: DayPlan }[] {
    return [...this.days.values()].sort((a, b) => compareDates(a.date, b.date));
  }
}

export type TodayScheduleStatus =
  | { type: 'noProgram' }
  | { type: 'dayNotScheduled' }
  | { type: 'restDay' }
  | { type: 'workoutDay'; workoutId: string; title: string }
  /** Same scheduled workout as `workoutDay`, but an incomplete session exists for today (user can continue logging). */
  | { type: 'workoutInProgress'; workoutId: string; title: string }
  /** Scheduled workout for today is already finished; offer Reopen instead of Start. */
  | { type: 'workoutAlreadyFinished'; workoutId: string; title: string };

/** Resolves "right now" using calendar-date schedule entries and workout titles. */
export function todayScheduleStatus(
  today: CalendarDate,
  schedule: ProgramCalendarSchedule,
  workoutNames: ReadonlyMap<string, string>,
): TodayScheduleStatus {
  const plan = schedule.plan(today);
  if (!plan) return { type: 'dayNotScheduled' };
  if (plan.type === 'rest') return { type: 'restDay' };
  return { type: 'workoutDay', workoutId: plan.workoutId, title: workoutNames.get(plan.workoutId) ?? 'Workout' };
}

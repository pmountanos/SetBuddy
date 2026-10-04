/**
 * A calendar day in the user's locale, independent of time-of-day.
 * Used as the canonical key for program schedule entries.
 */
export interface CalendarDate {
  year: number;
  /** 1...12 */
  month: number;
  /** 1...31 */
  day: number;
}

export function calendarDate(year: number, month: number, day: number): CalendarDate {
  return { year, month, day };
}

/** Adds `days` (may be negative) to a calendar date. Done in UTC so daylight-saving shifts can't skip a day. */
export function addDays(date: CalendarDate, days: number): CalendarDate {
  const shifted = new Date(Date.UTC(date.year, date.month - 1, date.day + days));
  return { year: shifted.getUTCFullYear(), month: shifted.getUTCMonth() + 1, day: shifted.getUTCDate() };
}

export function compareDates(a: CalendarDate, b: CalendarDate): number {
  return a.year - b.year || a.month - b.month || a.day - b.day;
}

export function sameDate(a: CalendarDate, b: CalendarDate): boolean {
  return compareDates(a, b) === 0;
}

/** Stable map key for a date (objects can't key a `Map` by value). */
export function dateKey(date: CalendarDate): string {
  return `${date.year}-${date.month}-${date.day}`;
}

/** `yyyy-MM-dd`, for display and exports. */
export function isoDate(date: CalendarDate): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${String(date.year).padStart(4, '0')}-${pad(date.month)}-${pad(date.day)}`;
}

/** The calendar date at `now` in the device's current time zone. */
export function calendarDateOf(now: Date): CalendarDate {
  return { year: now.getFullYear(), month: now.getMonth() + 1, day: now.getDate() };
}

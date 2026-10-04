import type { CalendarDate } from '@/domain/calendarDate';

/** Whole numbers without a decimal ("100"), otherwise as entered ("102.5"). */
export function formatNumber(value: number): string {
  return Number.isInteger(value) ? String(value) : String(Math.round(value * 100) / 100);
}

/** Volume in kg, rounded, with thousands separators. */
export function formatVolume(volume: number): string {
  return Math.round(volume).toLocaleString('en-US');
}

/** Accepts a comma or a dot as the decimal separator; anything unparseable or negative is 0. */
export function parseDecimal(text: string): number {
  const value = Number(text.replace(',', '.').trim());
  return Number.isFinite(value) && value > 0 ? value : 0;
}

export function parseWhole(text: string): number {
  const value = parseInt(text.trim(), 10);
  return Number.isFinite(value) && value > 0 ? value : 0;
}

const asLocalDate = (date: CalendarDate) => new Date(date.year, date.month - 1, date.day);

/** e.g. "Sun, Oct 4". */
export function formatDay(date: CalendarDate): string {
  return asLocalDate(date).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
}

/** e.g. "Oct 4, 2026". */
export function formatFullDay(date: CalendarDate): string {
  return asLocalDate(date).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
}

/** e.g. "Oct 4, 2026, 9:58 PM". */
export function formatTimestamp(epochMillis: number): string {
  if (!epochMillis) return '';
  return new Date(epochMillis).toLocaleString(undefined, { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' });
}

import Storage from 'expo-sqlite/kv-store';

/** Small on-device preferences (separate from the workout database). */

export const SCHEDULE_PREVIEW_CHOICES = [7, 14, 21] as const;
const SCHEDULE_PREVIEW_KEY = 'programSchedulePreviewDays';

/** How many upcoming days the Program tab lists. Defaults to 14. */
export function schedulePreviewDays(): number {
  const stored = Number(Storage.getItemSync(SCHEDULE_PREVIEW_KEY));
  return (SCHEDULE_PREVIEW_CHOICES as readonly number[]).includes(stored) ? stored : 14;
}

export function setSchedulePreviewDays(days: number): void {
  Storage.setItemSync(SCHEDULE_PREVIEW_KEY, String(days));
}

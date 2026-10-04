import * as Notifications from 'expo-notifications';
import { AndroidImportance } from 'expo-notifications';
import Storage from 'expo-sqlite/kv-store';
import { Platform, Settings } from 'react-native';

import type { LegacyImport } from '@/data/appDatabase';
import type { Services } from '@/state/AppContext';

import { clampReminderPrefs, DEFAULT_REMINDER_PREFS, planReminders, type ReminderPrefs } from './reminderPlan';

const PREFS_KEY = 'reminderPrefs';
const ANDROID_CHANNEL = 'daily-plan';

// Show the reminder even if the app happens to be open when it fires.
Notifications.setNotificationHandler({
  handleNotification: async () => ({ shouldShowBanner: true, shouldShowList: true, shouldPlaySound: true, shouldSetBadge: false }),
});

export function loadReminderPrefs(): ReminderPrefs {
  try {
    const stored = Storage.getItemSync(PREFS_KEY);
    if (stored) return clampReminderPrefs({ ...DEFAULT_REMINDER_PREFS, ...JSON.parse(stored) });
  } catch {
    // Unreadable preference: fall through to the default.
  }
  return DEFAULT_REMINDER_PREFS;
}

export function saveReminderPrefs(prefs: ReminderPrefs): void {
  Storage.setItemSync(PREFS_KEY, JSON.stringify(clampReminderPrefs(prefs)));
}

/**
 * On the launch that imports the native iOS app's data, also carry over its reminder setting (stored in
 * `UserDefaults`), so reminders keep arriving after the upgrade. The native app treated "never changed" as on at
 * 08:00. The native Android app's setting can't be read from here; Android starts with reminders off.
 */
export function migrateLegacyReminderPrefs(legacyImport: LegacyImport): void {
  if (Platform.OS !== 'ios' || legacyImport.source !== 'swiftdata-store' || Storage.getItemSync(PREFS_KEY)) return;
  const enabled: unknown = Settings.get('notificationSettings.dailyRemindersEnabled');
  const hour: unknown = Settings.get('notificationSettings.reminderHour');
  const minute: unknown = Settings.get('notificationSettings.reminderMinute');
  saveReminderPrefs({
    enabled: enabled === undefined || enabled === null ? true : enabled === true || enabled === 1,
    hour: typeof hour === 'number' ? hour : 8,
    minute: typeof minute === 'number' ? minute : 0,
  });
}

export async function reminderPermissionGranted(): Promise<boolean> {
  return (await Notifications.getPermissionsAsync()).granted;
}

/** Asks for notification permission if it hasn't been decided yet. Resolves to whether it is granted. */
export async function requestReminderPermission(): Promise<boolean> {
  const current = await Notifications.getPermissionsAsync();
  if (current.granted) return true;
  if (!current.canAskAgain) return false;
  return (await Notifications.requestPermissionsAsync()).granted;
}

let latestRun = 0;
let scheduledSignature: string | null = null;

/**
 * Replaces every pending reminder with the current plan. Call after anything that changes the schedule, the
 * program, or the reminder setting, and whenever the app returns to the foreground (which rolls the 14-day
 * window forward). Also clears reminders left pending by the native app this build replaced.
 */
export async function rescheduleReminders(services: Services, options: { force?: boolean } = {}): Promise<void> {
  const prefs = loadReminderPrefs();
  const program = services.programs.activeProgram();
  const planned = planReminders({
    prefs,
    today: services.env.today(),
    now: new Date(services.env.now()),
    schedule: program ? services.programs.calendarSchedule(program.id) : null,
    workoutTitles: program ? services.programs.workoutTitles(program.id) : new Map(),
  });

  // Screens refresh often; only touch the system's pending list when the plan actually differs.
  const signature = JSON.stringify(planned.map((reminder) => [reminder.id, reminder.fireAt.getTime(), reminder.title, reminder.body]));
  if (!options.force && signature === scheduledSignature) return;
  const run = ++latestRun;
  scheduledSignature = null;

  await Notifications.cancelAllScheduledNotificationsAsync();
  if (planned.length === 0 || !(await reminderPermissionGranted())) {
    if (planned.length === 0) scheduledSignature = signature;
    return;
  }
  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync(ANDROID_CHANNEL, { name: 'Daily plan reminder', importance: AndroidImportance.DEFAULT });
  }
  for (const reminder of planned) {
    // A newer reschedule has started (e.g. several edits in a row); let it finish the job.
    if (run !== latestRun) return;
    await Notifications.scheduleNotificationAsync({
      identifier: reminder.id,
      content: { title: reminder.title, body: reminder.body },
      trigger: { type: Notifications.SchedulableTriggerInputTypes.DATE, date: reminder.fireAt, channelId: ANDROID_CHANNEL },
    });
  }
  scheduledSignature = signature;
}

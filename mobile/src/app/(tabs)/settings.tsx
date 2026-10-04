import DateTimePicker, { DateTimePickerAndroid } from '@react-native-community/datetimepicker';
import Constants from 'expo-constants';
import { useState } from 'react';
import { Linking, Platform, StyleSheet, Switch, Text, View } from 'react-native';

import { historyCsv, historyXlsx } from '@/export/historyExport';
import { programCsv, programXlsx } from '@/export/programExport';
import type { ReminderPrefs } from '@/notifications/reminderPlan';
import { loadReminderPrefs, requestReminderPermission, rescheduleReminders, saveReminderPrefs } from '@/notifications/reminders';
import { pickProgramWorkbook, type PickedWorkbook, shareExport } from '@/settings/importExport';
import { SCHEDULE_PREVIEW_CHOICES, schedulePreviewDays, setSchedulePreviewDays } from '@/settings/preferences';
import { useApp } from '@/state/AppContext';
import { ImportStaging } from '@/ui/ImportStaging';
import { Body, Button, Card, Divider, Row, Screen, SectionTitle, Segmented } from '@/ui/kit';
import { useTheme } from '@/ui/theme';

function versionLabel(): string {
  const config = Constants.expoConfig;
  const build = Platform.OS === 'ios' ? config?.ios?.buildNumber : config?.android?.versionCode;
  return `Version ${config?.version ?? '?'}${build ? ` (${build})` : ''}`;
}

export default function SettingsScreen() {
  const theme = useTheme();
  const { services, refresh } = useApp();
  const [previewDays, setPreviewDays] = useState(schedulePreviewDays);
  const [staged, setStaged] = useState<PickedWorkbook | null>(null);
  const [message, setMessage] = useState<{ text: string; isError: boolean } | null>(null);
  const [busy, setBusy] = useState(false);
  const [reminders, setReminders] = useState(loadReminderPrefs);
  const [reminderBlocked, setReminderBlocked] = useState(false);

  const applyReminders = (prefs: ReminderPrefs) => {
    saveReminderPrefs(prefs);
    setReminders(prefs);
    void rescheduleReminders(services, { force: true }).catch(() => {});
  };
  const toggleReminders = async (enabled: boolean) => {
    if (enabled && !(await requestReminderPermission())) {
      // Permission was refused; only the system Settings app can change that now.
      setReminderBlocked(true);
      return;
    }
    setReminderBlocked(false);
    applyReminders({ ...reminders, enabled });
  };
  const reminderTime = new Date(2000, 0, 1, reminders.hour, reminders.minute);
  const setReminderTime = (date: Date | undefined) => {
    if (date) applyReminders({ ...reminders, hour: date.getHours(), minute: date.getMinutes() });
  };

  const run = async (task: () => Promise<void>) => {
    setBusy(true);
    setMessage(null);
    try {
      await task();
    } catch (error) {
      setMessage({ text: error instanceof Error ? error.message : 'Something went wrong.', isError: true });
    } finally {
      setBusy(false);
    }
  };

  const importWorkbook = () =>
    run(async () => {
      const picked = await pickProgramWorkbook();
      if (picked) setStaged(picked);
    });

  const exportProgram = () =>
    run(async () => {
      const outline = services.outlines.activeProgramOutline();
      if (!outline) throw new Error('There is no program to export. Create or import one on the Program tab.');
      const schedule = services.programs.calendarSchedule(outline.programId);
      await shareExport('Set_Buddy_Program', () => programXlsx(outline), () => programCsv(outline, schedule));
    });

  const exportHistory = () =>
    run(async () => {
      const sessions = services.history.allCompletedSessionDetails();
      await shareExport('Set_Buddy_History', () => historyXlsx(sessions), () => historyCsv(sessions));
    });

  return (
    <Screen title="Settings">
      <SectionTitle>How it works</SectionTitle>
      <Card style={styles.padded}>
        <Body secondary>
          Set Buddy uses one active training program. Build it on the Program tab (Start over there resets to a fresh starter), or import a spreadsheet here.
          Replacing the program clears in‑progress workouts; completed sessions remain in History.
        </Body>
      </Card>

      <SectionTitle>Notifications</SectionTitle>
      <Card style={styles.padded}>
        <View style={styles.switchRow}>
          <Body>Daily plan reminder</Body>
          <Switch accessibilityLabel="Daily plan reminder" testID="settingsReminderSwitch" value={reminders.enabled} onValueChange={toggleReminders} />
        </View>
        {reminders.enabled ? (
          <>
            <Divider />
            {Platform.OS === 'ios' ? (
              <View style={styles.switchRow}>
                <Body>Reminder time</Body>
                <DateTimePicker mode="time" display="compact" value={reminderTime} onChange={(_, date) => setReminderTime(date)} />
              </View>
            ) : (
              <Row
                testID="settingsReminderTime"
                trailing={reminderTime.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}
                onPress={() => DateTimePickerAndroid.open({ mode: 'time', value: reminderTime, onChange: (_, date) => setReminderTime(date) })}>
                <Body>Reminder time</Body>
              </Row>
            )}
          </>
        ) : null}
        <Body secondary style={styles.small}>
          One notification a day telling you whether it’s a workout or a rest day.
        </Body>
        {Platform.OS === 'android' && reminders.enabled ? (
          <>
            <Body secondary style={styles.small}>
              Android may deliver the reminder up to an hour late unless Set Buddy is allowed under “Alarms & reminders”.
            </Body>
            <Button
              label="Open Alarms & reminders"
              kind="plain"
              compact
              onPress={() => void Linking.sendIntent('android.settings.REQUEST_SCHEDULE_EXACT_ALARM').catch(() => Linking.openSettings())}
            />
          </>
        ) : null}
        {reminderBlocked ? (
          <>
            <Text style={[styles.small, { color: theme.danger }]}>Notifications are turned off for Set Buddy. Allow them in system Settings, then switch this on.</Text>
            <Button label="Open system Settings" kind="plain" compact onPress={() => void Linking.openSettings()} />
          </>
        ) : null}
      </Card>

      <SectionTitle>Program</SectionTitle>
      <Card style={styles.padded}>
        <Body>Upcoming schedule length</Body>
        <Segmented
          value={previewDays}
          options={SCHEDULE_PREVIEW_CHOICES.map((days) => ({ label: `${days} days`, value: days as number }))}
          onChange={(days) => {
            setSchedulePreviewDays(days);
            setPreviewDays(days);
            refresh();
          }}
        />
        <Body secondary style={styles.small}>
          Import an .xlsx workbook with one worksheet per day of your rotation. A sheet named “Rest” (or an empty one) is a rest day.
        </Body>
        <Button label="Import program (.xlsx)" kind="secondary" disabled={busy} testID="settingsImport" onPress={importWorkbook} />
      </Card>

      <SectionTitle>Export</SectionTitle>
      <Card style={styles.padded}>
        <Button label="Export program" kind="secondary" disabled={busy} testID="settingsExportProgram" onPress={exportProgram} />
        <Button label="Export workout history" kind="secondary" disabled={busy} testID="settingsExportHistory" onPress={exportHistory} />
        <Body secondary style={styles.small}>
          Spreadsheets (.xlsx). The program export can be imported back; the history export has one row per logged set.
        </Body>
      </Card>

      {message ? (
        <Text style={[styles.message, { color: message.isError ? theme.danger : theme.text }]} testID="settingsMessage">
          {message.text}
        </Text>
      ) : null}
      <Text style={[styles.version, { color: theme.tertiary }]}>{versionLabel()}</Text>

      {staged ? <ImportStaging workbook={staged} onClose={() => setStaged(null)} onImported={(text) => setMessage({ text, isError: false })} /> : null}
    </Screen>
  );
}

const styles = StyleSheet.create({
  padded: { paddingVertical: 12, gap: 10 },
  switchRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', minHeight: 44 },
  small: { fontSize: 13, lineHeight: 18 },
  message: { fontSize: 15, lineHeight: 21, textAlign: 'center', marginTop: 4 },
  version: { fontSize: 13, textAlign: 'center', marginTop: 8 },
});

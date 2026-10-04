import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { REST, type TodayScheduleStatus, workoutPlan } from '@/domain/schedule';
import { useApp, useData } from '@/state/AppContext';
import { changeTodaysPlan, resolveTodayStatus } from '@/state/todayStatus';
import { formatDay } from '@/ui/format';
import { Button, OptionSheet, Screen } from '@/ui/kit';
import { useTheme } from '@/ui/theme';

function headline(status: TodayScheduleStatus): string {
  switch (status.type) {
    case 'noProgram':
      return 'No program yet';
    case 'dayNotScheduled':
      return 'Nothing scheduled';
    case 'restDay':
      return 'Rest day';
    default:
      return status.title;
  }
}

function detail(status: TodayScheduleStatus): string {
  switch (status.type) {
    case 'noProgram':
      return 'Create a program on the Program tab, or import a spreadsheet in Settings.';
    case 'dayNotScheduled':
      return 'Today is outside your program’s schedule. Pick a workout below, or set the schedule on the Program tab.';
    case 'restDay':
      return 'Recovery is part of training.';
    case 'workoutDay':
      return 'Start below when you’re ready to log sets.';
    case 'workoutInProgress':
      return 'You have a session in progress. Continue on the Workout tab or below.';
    case 'workoutAlreadyFinished':
      return 'You’ve already logged this session today. Reopen it if you finished by mistake.';
  }
}

export default function TodayScreen() {
  const theme = useTheme();
  const router = useRouter();
  const { services, refresh, setOpenWorkout } = useApp();
  const [planMenuOpen, setPlanMenuOpen] = useState(false);

  // Coming back to this tab re-reads status (e.g. after finishing a workout, or after midnight).
  useFocusEffect(useCallback(() => refresh(), [refresh]));

  const status = useData(resolveTodayStatus);
  const today = useData((s) => s.env.today());
  const workouts = useData((s) => {
    const program = s.programs.activeProgram();
    return program ? s.programs.workouts(program.id) : [];
  });

  const startLogging = (workoutId: string) => {
    setOpenWorkout({ workoutId, date: today });
    router.navigate('/workout');
  };

  return (
    <Screen scroll={false}>
      <View style={styles.center}>
        <Text style={[styles.date, { color: theme.secondary }]}>{formatDay(today)}</Text>
        <Text style={[styles.headline, { color: theme.text }]} testID="todayHeadline">
          {headline(status)}
        </Text>
        {status.type === 'workoutAlreadyFinished' ? <Text style={[styles.done, { color: theme.accent }]}>Finished for today ✓</Text> : null}
        <Text style={[styles.detail, { color: theme.secondary }]}>{detail(status)}</Text>

        <View style={styles.actions}>
          {status.type === 'workoutDay' ? (
            <Button label={`Start ${status.title}`} testID="todayStartWorkoutButton" onPress={() => startLogging(status.workoutId)} />
          ) : null}
          {status.type === 'workoutInProgress' ? (
            <Button label={`Continue ${status.title}`} testID="todayContinueWorkoutButton" onPress={() => startLogging(status.workoutId)} />
          ) : null}
          {status.type === 'workoutAlreadyFinished' ? (
            <Button
              label={`Reopen ${status.title}`}
              kind="secondary"
              testID="todayReopenWorkoutButton"
              onPress={() => {
                services.sessions.reopenCompletedSession(status.workoutId, today);
                refresh();
                startLogging(status.workoutId);
              }}
            />
          ) : null}
          {status.type !== 'noProgram' ? (
            <Button label="Change today’s plan" kind="plain" testID="todayChangePlanButton" onPress={() => setPlanMenuOpen(true)} />
          ) : null}
        </View>
      </View>

      <OptionSheet
        visible={planMenuOpen}
        title="Change today’s plan — later days shift to keep your rotation in order"
        onClose={() => setPlanMenuOpen(false)}
        options={[
          { label: 'Rest', selected: status.type === 'restDay', onPress: () => (changeTodaysPlan(services, REST), refresh()) },
          ...workouts.map((workout) => ({
            label: workout.name,
            selected: 'workoutId' in status && status.workoutId === workout.id,
            onPress: () => (changeTodaysPlan(services, workoutPlan(workout.id)), refresh()),
          })),
        ]}
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 28, gap: 8 },
  date: { fontSize: 15, fontWeight: '600', textTransform: 'uppercase', letterSpacing: 0.5 },
  headline: { fontSize: 34, fontWeight: '700', textAlign: 'center' },
  done: { fontSize: 17, fontWeight: '600' },
  detail: { fontSize: 16, lineHeight: 22, textAlign: 'center' },
  actions: { alignSelf: 'stretch', gap: 10, marginTop: 24 },
});

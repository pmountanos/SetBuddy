import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback } from 'react';

import { dateKey } from '@/domain/calendarDate';
import { useApp, useData } from '@/state/AppContext';
import { resolveTodayStatus } from '@/state/todayStatus';
import { Button, EmptyState, Screen } from '@/ui/kit';
import { WorkoutLogger } from '@/ui/WorkoutLogger';

export default function WorkoutScreen() {
  const router = useRouter();
  const { openWorkout, setOpenWorkout, refresh } = useApp();
  useFocusEffect(useCallback(() => refresh(), [refresh]));

  // Whatever Today opened, else a session already in progress for today's scheduled workout.
  const inProgress = useData((services) => {
    const status = resolveTodayStatus(services);
    return status.type === 'workoutInProgress' ? { workoutId: status.workoutId, date: services.env.today() } : null;
  });
  const target = openWorkout ?? inProgress;
  const stillExists = useData((services) => (target ? services.programs.workout(target.workoutId) !== null : false));

  if (!target || !stillExists) {
    return (
      <Screen scroll={false}>
        <EmptyState title="No workout in progress" message="Start today’s workout from the Today tab and it will open here.">
          <Button label="Go to Today" kind="secondary" onPress={() => router.navigate('/')} />
        </EmptyState>
      </Screen>
    );
  }

  return (
    <WorkoutLogger
      key={`${target.workoutId}/${dateKey(target.date)}`}
      workoutId={target.workoutId}
      date={target.date}
      onFinished={() => {
        setOpenWorkout(null);
        router.navigate('/');
      }}
    />
  );
}

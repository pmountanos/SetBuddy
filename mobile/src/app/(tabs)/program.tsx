import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, StyleSheet, Text, TextInput, View } from 'react-native';

import type { Exercise } from '@/data/models';
import type { ProgramScheduleDayRow } from '@/data/outlineRepository';
import { sameDate } from '@/domain/calendarDate';
import { REST, workoutPlan } from '@/domain/schedule';
import { schedulePreviewDays } from '@/settings/preferences';
import { useApp, useData } from '@/state/AppContext';
import { formatDay } from '@/ui/format';
import { Body, Button, Card, Divider, EmptyState, OptionSheet, Row, Screen, SectionTitle, TextPrompt } from '@/ui/kit';
import { useTheme } from '@/ui/theme';
import { WorkoutEditor } from '@/ui/WorkoutEditor';

function exerciseSummary(exercise: Exercise): string {
  const sets = `${exercise.setCount} ${exercise.setCount === 1 ? 'set' : 'sets'}`;
  if (exercise.kind === 'cardio') return `${sets} · Cardio`;
  return exercise.repsArePerSide ? `${sets} · Per side ×2` : sets;
}

export default function ProgramScreen() {
  const theme = useTheme();
  const { services, refresh } = useApp();
  const { programs } = services;
  useFocusEffect(useCallback(() => refresh(), [refresh]));

  const outline = useData((s) => {
    s.programs.ensureForwardScheduleFilled();
    return s.outlines.activeProgramOutline();
  });
  const upcoming = useData((s) => s.outlines.upcomingScheduleRows(schedulePreviewDays()));
  const today = useData((s) => s.env.today());

  // The name field is a draft; it follows the stored name whenever that changes (rename, import, start over).
  const storedName = outline?.programName ?? '';
  const [name, setName] = useState(storedName);
  const [syncedName, setSyncedName] = useState(storedName);
  if (syncedName !== storedName) {
    setSyncedName(storedName);
    setName(storedName);
  }
  const [dayMenu, setDayMenu] = useState<ProgramScheduleDayRow | null>(null);
  const [editingWorkoutId, setEditingWorkoutId] = useState<string | null>(null);
  const [noteFor, setNoteFor] = useState<Exercise | null>(null);

  if (!outline) {
    return (
      <Screen scroll={false}>
        <EmptyState title="No program yet" message="Create a starter program here and edit it, or import a spreadsheet from Settings.">
          <Button label="Create program" testID="programCreateButton" onPress={() => (programs.createFirstProgram('My program'), refresh())} />
        </EmptyState>
      </Screen>
    );
  }

  const confirmStartOver = () =>
    Alert.alert(
      'Start over?',
      'Your current program and schedule are removed and replaced with a fresh starter. Completed workouts stay in History; any workout in progress is cleared.',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Start over', style: 'destructive', onPress: () => (programs.startOverFreshProgram(name), refresh()) },
      ],
    );

  return (
    <Screen title="Program">
      <TextInput
        accessibilityLabel="Program name"
        testID="programName"
        value={name}
        onChangeText={setName}
        onEndEditing={() => (programs.renameProgram(name), refresh())}
        returnKeyType="done"
        style={[styles.nameInput, { color: theme.text, backgroundColor: theme.card, borderColor: theme.border }]}
      />
      <View style={styles.buttonRow}>
        <View style={styles.flex}>
          <Button label="Add workout" kind="secondary" compact testID="programAddWorkout" onPress={() => setEditingWorkoutId(programs.addWorkout().id)} />
        </View>
        <View style={styles.flex}>
          <Button label="Start over" kind="danger" compact onPress={confirmStartOver} />
        </View>
      </View>

      <SectionTitle>Upcoming schedule</SectionTitle>
      <Card>
        {upcoming.map((row, index) => (
          <View key={`${row.date.year}-${row.date.month}-${row.date.day}`}>
            {index > 0 ? <Divider /> : null}
            <Row onPress={() => setDayMenu(row)} trailing={row.isRestDay ? 'Rest' : (row.workoutTitle ?? 'Workout')}>
              <Body>{sameDate(row.date, today) ? `Today · ${formatDay(row.date)}` : formatDay(row.date)}</Body>
            </Row>
          </View>
        ))}
      </Card>

      <SectionTitle>Workouts</SectionTitle>
      {outline.workouts.map((workout) => (
        <Card key={workout.id} style={styles.workoutCard}>
          <Row onPress={() => setEditingWorkoutId(workout.id)} trailing="Edit" testID={`programEditWorkout-${workout.name}`}>
            <Text style={[styles.workoutName, { color: theme.text }]}>{workout.name}</Text>
          </Row>
          {workout.exercises.map((exercise) => (
            <View key={exercise.id}>
              <Divider />
              <Row onPress={() => setNoteFor(exercise)}>
                <Body>{exercise.name}</Body>
                <Text style={[styles.meta, { color: theme.secondary }]}>
                  {exerciseSummary(exercise)}
                  {exercise.note ? ' · Has note' : ''}
                </Text>
              </Row>
            </View>
          ))}
          {workout.exercises.length === 0 ? <Body secondary>No exercises yet — tap Edit to add some.</Body> : null}
        </Card>
      ))}

      <OptionSheet
        visible={dayMenu !== null}
        title={dayMenu ? `${formatDay(dayMenu.date)} — later days shift to keep your rotation in order` : ''}
        onClose={() => setDayMenu(null)}
        options={
          dayMenu
            ? [
                { label: 'Rest', selected: dayMenu.isRestDay, onPress: () => (programs.setScheduleDayShiftingFollowing(dayMenu.date, REST), refresh()) },
                ...outline.workouts.map((workout) => ({
                  label: workout.name,
                  selected: dayMenu.workoutId === workout.id,
                  onPress: () => (programs.setScheduleDayShiftingFollowing(dayMenu.date, workoutPlan(workout.id)), refresh()),
                })),
                { label: 'Add a rest day here', onPress: () => (programs.insertRestDayShiftingFollowing(dayMenu.date), refresh()) },
              ]
            : []
        }
      />
      <TextPrompt
        visible={noteFor !== null}
        title={noteFor ? `${noteFor.name} — note` : ''}
        initialText={noteFor?.note ?? ''}
        placeholder="Cues, setup, tempo…"
        onClose={() => setNoteFor(null)}
        onSave={(text) => {
          if (noteFor) programs.setExerciseNote(noteFor.id, text);
          refresh();
        }}
      />
      {editingWorkoutId ? <WorkoutEditor workoutId={editingWorkoutId} onClose={() => setEditingWorkoutId(null)} /> : null}
    </Screen>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  nameInput: { minHeight: 48, borderWidth: StyleSheet.hairlineWidth, borderRadius: 12, paddingHorizontal: 14, fontSize: 18, fontWeight: '600' },
  buttonRow: { flexDirection: 'row', gap: 10 },
  workoutCard: { paddingVertical: 2 },
  workoutName: { fontSize: 18, fontWeight: '600' },
  meta: { fontSize: 13, marginTop: 2 },
});

import { useMemo, useState } from 'react';
import { Alert, KeyboardAvoidingView, Modal, Pressable, ScrollView, StyleSheet, Switch, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import type { Exercise } from '@/data/models';
import type { ExerciseKind } from '@/domain/exerciseKind';
import { useApp } from '@/state/AppContext';

import { Button, Divider, Segmented, Stepper } from './kit';
import { useTheme } from './theme';

/** Edits one workout template: its name and its exercises (name, type, sets, per-side, order, add/remove). */
export function WorkoutEditor({ workoutId, onClose }: { workoutId: string; onClose: () => void }) {
  const theme = useTheme();
  const { services, refresh } = useApp();
  const { programs } = services;
  const [revision, setRevision] = useState(0);
  // eslint-disable-next-line react-hooks/exhaustive-deps -- `revision` invalidates after each write
  const workout = useMemo(() => programs.workout(workoutId), [revision]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const exercises = useMemo(() => programs.exercises(workoutId), [revision]);
  const [name, setName] = useState(workout?.name ?? '');

  const changed = () => {
    setRevision((r) => r + 1);
    refresh();
  };
  const close = () => {
    programs.renameWorkout(workoutId, name);
    refresh();
    onClose();
  };
  const move = (index: number, delta: number) => {
    const ids = exercises.map((exercise) => exercise.id);
    const [id] = ids.splice(index, 1);
    ids.splice(index + delta, 0, id);
    programs.reorderExercises(ids);
    changed();
  };
  const confirmDeleteWorkout = () =>
    Alert.alert(`Delete “${workout?.name ?? 'workout'}”?`, 'Scheduled days that used this workout become rest days. Completed sessions stay in History.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () => {
          programs.deleteWorkout(workoutId);
          refresh();
          onClose();
        },
      },
    ]);

  return (
    <Modal visible animationType="slide" presentationStyle="pageSheet" onRequestClose={close}>
      <SafeAreaView style={[styles.flex, { backgroundColor: theme.background }]}>
        <KeyboardAvoidingView style={styles.flex} behavior="padding">
          <View style={styles.header}>
            <Text style={[styles.title, { color: theme.text }]}>Edit workout</Text>
            <Button label="Done" compact testID="workoutEditorDone" onPress={close} />
          </View>
          <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
            <TextInput
              accessibilityLabel="Workout name"
              testID="workoutEditorName"
              value={name}
              onChangeText={setName}
              onEndEditing={() => (programs.renameWorkout(workoutId, name), refresh())}
              placeholder="Workout name"
              placeholderTextColor={theme.tertiary}
              style={[styles.input, styles.nameInput, { color: theme.text, backgroundColor: theme.card, borderColor: theme.border }]}
            />
            {exercises.map((exercise, index) => (
              <ExerciseEditor
                key={exercise.id}
                exercise={exercise}
                canMoveUp={index > 0}
                canMoveDown={index < exercises.length - 1}
                onMove={(delta) => move(index, delta)}
                onChanged={changed}
              />
            ))}
            <Button label="Add exercise" kind="secondary" testID="workoutEditorAddExercise" onPress={() => (programs.addExercise(workoutId), changed())} />
            <Button label="Delete workout" kind="danger" onPress={confirmDeleteWorkout} />
          </ScrollView>
        </KeyboardAvoidingView>
      </SafeAreaView>
    </Modal>
  );
}

function ExerciseEditor({
  exercise,
  canMoveUp,
  canMoveDown,
  onMove,
  onChanged,
}: {
  exercise: Exercise;
  canMoveUp: boolean;
  canMoveDown: boolean;
  onMove: (delta: number) => void;
  onChanged: () => void;
}) {
  const theme = useTheme();
  const { programs } = useApp().services;
  const [name, setName] = useState(exercise.name);

  const iconButton = (label: string, glyph: string, onPress: () => void, enabled = true, color = theme.accent) => (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      disabled={!enabled}
      onPress={onPress}
      style={({ pressed }) => [styles.iconButton, { opacity: !enabled ? 0.25 : pressed ? 0.6 : 1 }]}>
      <Text style={[styles.iconGlyph, { color }]}>{glyph}</Text>
    </Pressable>
  );

  return (
    <View style={[styles.exercise, { backgroundColor: theme.card }]}>
      <View style={styles.nameRow}>
        <TextInput
          accessibilityLabel="Exercise name"
          value={name}
          onChangeText={(text) => {
            setName(text);
            programs.setExerciseName(exercise.id, text);
          }}
          onEndEditing={onChanged}
          placeholder="Exercise name"
          placeholderTextColor={theme.tertiary}
          style={[styles.input, styles.flex, { color: theme.text, borderColor: theme.border }]}
        />
        {iconButton(`Move ${exercise.name} up`, '↑', () => onMove(-1), canMoveUp)}
        {iconButton(`Move ${exercise.name} down`, '↓', () => onMove(1), canMoveDown)}
        {iconButton(`Delete ${exercise.name}`, '✕', () => (programs.deleteExercise(exercise.id), onChanged()), true, theme.danger)}
      </View>
      <Segmented<ExerciseKind>
        value={exercise.kind}
        options={[
          { label: 'Strength', value: 'strength' },
          { label: 'Cardio', value: 'cardio' },
        ]}
        onChange={(kind) => {
          if (kind !== exercise.kind) programs.setExerciseKind(exercise.id, kind);
          onChanged();
        }}
      />
      <Stepper
        label={`Sets to log: ${exercise.setCount}`}
        value={exercise.setCount}
        min={1}
        max={20}
        onChange={(count) => (programs.setExerciseSetCount(exercise.id, count), onChanged())}
      />
      <Divider />
      {exercise.kind === 'strength' ? (
        <View style={styles.switchRow}>
          <Text style={[styles.switchLabel, { color: theme.text }]}>Per side — volume ×2</Text>
          <Switch
            accessibilityLabel="Per side"
            value={exercise.repsArePerSide}
            onValueChange={(value) => (programs.setExerciseRepsPerSide(exercise.id, value), onChanged())}
          />
        </View>
      ) : (
        <Text style={[styles.hint, { color: theme.secondary }]}>Cardio sets log minutes and max heart rate instead of weight/reps.</Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingTop: 16, paddingBottom: 8 },
  title: { fontSize: 24, fontWeight: '700' },
  content: { padding: 16, gap: 12, paddingBottom: 48 },
  input: { minHeight: 44, borderWidth: 1, borderRadius: 10, paddingHorizontal: 12, fontSize: 16 },
  nameInput: { fontSize: 18, fontWeight: '600' },
  exercise: { borderRadius: 14, padding: 12, gap: 10 },
  nameRow: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  iconButton: { width: 40, height: 44, alignItems: 'center', justifyContent: 'center' },
  iconGlyph: { fontSize: 20, fontWeight: '600' },
  switchRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', minHeight: 44 },
  switchLabel: { fontSize: 16 },
  hint: { fontSize: 14, lineHeight: 19 },
});

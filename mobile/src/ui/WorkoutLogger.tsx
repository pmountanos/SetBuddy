import { type ReactNode, useEffect, useMemo, useState } from 'react';
import { Alert, Keyboard, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { SafeAreaView as NativeSafeAreaView } from 'react-native-screens/experimental';

import type { Exercise, LoggedSet } from '@/data/models';
import type { CalendarDate } from '@/domain/calendarDate';
import { setVolume } from '@/domain/volume';
import { useApp } from '@/state/AppContext';

import { formatNumber, formatVolume, parseDecimal, parseWhole } from './format';
import { Button, TextPrompt } from './kit';
import { type Theme, useTheme } from './theme';

/**
 * The logging screen for one workout on one day. Each set shows the most recent logged values for that exercise
 * as an orange **reference**; once the user commits a set (edited, or just confirmed by touching it) it switches
 * to the high-contrast **entered** style. Only entered sets are saved when the workout is finished.
 */
export function WorkoutLogger({ workoutId, date, onFinished }: { workoutId: string; date: CalendarDate; onFinished: () => void }) {
  const theme = useTheme();
  const { services, refresh } = useApp();
  const { programs, sessions } = services;

  // Opening the logger starts (or resumes) today's session for this workout.
  const [session] = useState(() => sessions.getOrCreateActiveSession(workoutId, date));
  const [reference] = useState(() => sessions.mostRecentLoggedValuesByExercise());
  const [revision, setRevision] = useState(0);
  const [editingNoteFor, setEditingNoteFor] = useState<Exercise | null>(null);
  const [editingSessionNote, setEditingSessionNote] = useState(false);
  const [keyboardVisible, setKeyboardVisible] = useState(false);

  useEffect(() => {
    const show = Keyboard.addListener(Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow', () => setKeyboardVisible(true));
    const hide = Keyboard.addListener(Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide', () => {
      setKeyboardVisible(false);
      // e.g. the Android back button hides the keyboard without ending the edit.
      TextInput.State.currentlyFocusedInput()?.blur();
    });
    return () => {
      show.remove();
      hide.remove();
    };
  }, []);

  // eslint-disable-next-line react-hooks/exhaustive-deps -- `revision` invalidates after each write
  const workout = useMemo(() => programs.workout(workoutId), [revision]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const exercises = useMemo(() => programs.exercises(workoutId), [revision]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const loggedByKey = useMemo(() => new Map(sessions.loggedSets(session.id).map((set) => [`${set.exerciseId}/${set.setIndex}`, set])), [revision]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const sessionNote = useMemo(() => sessions.session(session.id)?.sessionNote ?? '', [revision]);

  const sessionVolume = exercises
    .filter((exercise) => exercise.kind === 'strength')
    .reduce((total, exercise) => {
      for (let setIndex = 0; setIndex < exercise.setCount; setIndex++) {
        const set = loggedByKey.get(`${exercise.id}/${setIndex}`);
        if (set?.userEditedValues) total += setVolume(set.weight, set.reps, exercise.repsArePerSide);
      }
      return total;
    }, 0);

  const commit = (exercise: Exercise, setIndex: number, first: number, second: number) => {
    if (exercise.kind === 'cardio') sessions.updateCardioLoggedSet(session.id, exercise.id, setIndex, first, second);
    else sessions.updateLoggedSet(session.id, exercise.id, setIndex, first, second);
    setRevision((r) => r + 1);
  };

  const finish = () => {
    // Ending the edit confirms the set being touched; let that settle before asking.
    endEditing();
    setTimeout(() => {
      Alert.alert('Finish workout?', 'Only sets you entered are saved. Values from your last workout are for reference only.', [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Finish',
          onPress: () => {
            sessions.completeSession(session.id, workout?.name ?? 'Workout');
            refresh();
            onFinished();
          },
        },
      ]);
    }, 150);
  };

  return (
    <SafeAreaView style={[styles.flex, { backgroundColor: theme.background }]} edges={['top', 'left', 'right']}>
      <AboveTabBar>
        <KeyboardAvoidingView style={styles.flex} behavior="padding">
          <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag">
            <Text style={[styles.title, { color: theme.text }]} testID="workoutTitle">
              {workout?.name ?? 'Workout'}
            </Text>
            {exercises.map((exercise) => (
              <View key={exercise.id} style={[styles.exercise, { backgroundColor: theme.card }]}>
                <Pressable accessibilityRole="button" accessibilityLabel={`${exercise.name}, notes`} onPress={() => setEditingNoteFor(exercise)}>
                  <Text style={[styles.exerciseName, { color: theme.text }]}>{exercise.name}</Text>
                  <Text style={[styles.exerciseMeta, { color: theme.secondary }]}>
                    {exercise.kind === 'cardio' ? 'Cardio' : exercise.repsArePerSide ? 'Per side — volume ×2' : 'Strength'}
                    {exercise.note ? ' · Note ›' : ' · Add note ›'}
                  </Text>
                  {exercise.note ? <Text style={[styles.note, { color: theme.secondary }]}>{exercise.note}</Text> : null}
                </Pressable>
                {Array.from({ length: exercise.setCount }, (_, setIndex) => (
                  <SetRow
                    key={setIndex}
                    theme={theme}
                    exercise={exercise}
                    setIndex={setIndex}
                    logged={loggedByKey.get(`${exercise.id}/${setIndex}`)}
                    reference={reference.get(exercise.id)?.get(setIndex)}
                    onCommit={(first, second) => commit(exercise, setIndex, first, second)}
                  />
                ))}
              </View>
            ))}
            {exercises.length === 0 ? <Text style={[styles.exerciseMeta, { color: theme.secondary }]}>This workout has no exercises yet. Add some on the Program tab.</Text> : null}
          </ScrollView>

          <View style={[styles.bar, { backgroundColor: theme.card, borderTopColor: theme.border }]}>
            <View style={styles.barVolume}>
              <Text style={[styles.barLabel, { color: theme.secondary }]}>Session volume</Text>
              <Text style={[styles.barValue, { color: theme.text }]} testID="sessionVolume">
                {formatVolume(sessionVolume)} kg
              </Text>
            </View>
            {keyboardVisible ? (
              // Number pads have no Return key; this is how the keyboard is dismissed.
              <Button label="Done" compact testID="workoutDoneButton" onPress={endEditing} />
            ) : (
              <>
                <Button label={sessionNote ? 'Edit note' : 'Note'} kind="plain" compact onPress={() => setEditingSessionNote(true)} />
                <Button label="Finish" compact testID="workoutFinishButton" onPress={finish} />
              </>
            )}
          </View>
        </KeyboardAvoidingView>
      </AboveTabBar>

      <TextPrompt
        visible={editingNoteFor !== null}
        title={editingNoteFor ? `${editingNoteFor.name} — note` : ''}
        initialText={editingNoteFor?.note ?? ''}
        placeholder="Cues, setup, tempo…"
        onClose={() => setEditingNoteFor(null)}
        onSave={(text) => {
          if (editingNoteFor) programs.setExerciseNote(editingNoteFor.id, text);
          setRevision((r) => r + 1);
          refresh();
        }}
      />
      <TextPrompt
        visible={editingSessionNote}
        title="Workout note"
        initialText={sessionNote}
        placeholder="How did it go?"
        onClose={() => setEditingSessionNote(false)}
        onSave={(text) => {
          sessions.setSessionNote(session.id, text);
          setRevision((r) => r + 1);
        }}
      />
    </SafeAreaView>
  );
}

/** Ends editing in whichever field has focus. On Android, hiding the keyboard alone leaves the field focused. */
function endEditing() {
  TextInput.State.currentlyFocusedInput()?.blur();
  Keyboard.dismiss();
}

/**
 * Keeps its content clear of the tab bar. On iPhone the tab bar floats over the screen, and only a scroll view
 * is moved out of its way automatically — a fixed bar at the bottom (Finish, Done, session volume) would sit
 * underneath it. On Android the tabs already reserve that space.
 */
function AboveTabBar({ children }: { children: ReactNode }) {
  if (Platform.OS !== 'ios') return <View style={styles.flex}>{children}</View>;
  return (
    <NativeSafeAreaView style={styles.flex} edges={{ bottom: true }}>
      {children}
    </NativeSafeAreaView>
  );
}

type Chrome = 'neutral' | 'reference' | 'entered';

/** What the two fields show for a set: the entered values, else the reference, else blank. */
function displayValues(kind: Exercise['kind'], logged: LoggedSet | undefined, reference: LoggedSet | undefined): [string, string] {
  const source = logged?.userEditedValues ? logged : reference;
  if (!source) return ['', ''];
  const [first, second] = kind === 'cardio' ? [source.cardioMinutes, source.maxHeartRate] : [source.weight, source.reps];
  return [first ? formatNumber(first) : '', second ? formatNumber(second) : ''];
}

function SetRow({
  theme,
  exercise,
  setIndex,
  logged,
  reference,
  onCommit,
}: {
  theme: Theme;
  exercise: Exercise;
  setIndex: number;
  logged: LoggedSet | undefined;
  reference: LoggedSet | undefined;
  onCommit: (first: number, second: number) => void;
}) {
  const isCardio = exercise.kind === 'cardio';
  const entered = logged?.userEditedValues ?? false;
  const [shownFirst, shownSecond] = displayValues(exercise.kind, logged, reference);
  const [first, setFirst] = useState(shownFirst);
  const [second, setSecond] = useState(shownSecond);
  const [focusedField, setFocusedField] = useState<'first' | 'second' | null>(null);

  // Follow stored values unless the user is mid-edit in this row. Edits are stored as they are typed, so this
  // only ever normalises what is already on screen (or picks up a change made elsewhere).
  const shownKey = `${shownFirst}|${shownSecond}`;
  const [syncedKey, setSyncedKey] = useState(shownKey);
  if (focusedField === null && syncedKey !== shownKey) {
    setSyncedKey(shownKey);
    setFirst(shownFirst);
    setSecond(shownSecond);
  }

  // A set cleared back to nothing looks (and on finish, is treated as) not entered.
  const chrome: Chrome = !(shownFirst || shownSecond) ? 'neutral' : entered ? 'entered' : 'reference';

  // An empty, never-entered set stays empty; anything else is stored and marks the set as entered.
  const store = (firstText: string, secondText: string) => {
    const a = parseDecimal(firstText);
    const b = parseWhole(secondText);
    if (!entered && a === 0 && b === 0) return;
    onCommit(a, b);
  };

  const field = (which: 'first' | 'second', label: string, value: string, setValue: (text: string) => void, decimal: boolean) => {
    const colors =
      chrome === 'entered'
        ? { backgroundColor: theme.entered, color: theme.onEntered, borderColor: theme.entered }
        : chrome === 'reference'
          ? { backgroundColor: theme.reference, color: theme.onReference, borderColor: theme.reference }
          : { backgroundColor: 'transparent', color: theme.text, borderColor: theme.border };
    return (
      <View style={styles.fieldBlock}>
        <Text style={[styles.fieldLabel, { color: theme.secondary }]}>{label}</Text>
        <TextInput
          testID={`set-${exercise.sortOrder}-${setIndex}-${which}`}
          accessibilityLabel={`${exercise.name} set ${setIndex + 1} ${label}`}
          accessibilityHint={chrome === 'reference' ? 'Value from your last completed session.' : undefined}
          value={value}
          onChangeText={(text) => {
            setValue(text);
            // Stored on every keystroke, so nothing depends on how (or whether) the field loses focus.
            if (which === 'first') store(text, second);
            else store(first, text);
          }}
          keyboardType={decimal ? 'decimal-pad' : 'number-pad'}
          placeholder="0"
          placeholderTextColor={chrome === 'neutral' ? theme.tertiary : colors.color}
          selectTextOnFocus
          onFocus={() => setFocusedField(which)}
          onBlur={() => {
            setFocusedField((current) => (current === which ? null : current));
            // Touching a set confirms it, even when left unchanged from the reference values.
            if (!entered) store(first, second);
          }}
          style={[styles.field, colors]}
        />
      </View>
    );
  };

  return (
    <View style={styles.setRow}>
      <Text style={[styles.setLabel, { color: theme.secondary }]}>Set {setIndex + 1}</Text>
      {field('first', isCardio ? 'Minutes' : 'Weight (kg)', first, setFirst, true)}
      {field('second', isCardio ? 'Max HR (bpm)' : exercise.repsArePerSide ? 'Reps / side' : 'Reps', second, setSecond, false)}
    </View>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  content: { padding: 16, paddingBottom: 32, gap: 12 },
  title: { fontSize: 30, fontWeight: '700' },
  exercise: { borderRadius: 14, padding: 14, gap: 10 },
  exerciseName: { fontSize: 19, fontWeight: '600' },
  exerciseMeta: { fontSize: 13, marginTop: 2 },
  note: { fontSize: 14, lineHeight: 19, marginTop: 6 },
  setRow: { flexDirection: 'row', alignItems: 'flex-end', gap: 12 },
  setLabel: { width: 48, fontSize: 14, fontWeight: '600', paddingBottom: 14 },
  fieldBlock: { flex: 1, gap: 4 },
  fieldLabel: { fontSize: 12 },
  field: { minHeight: 48, borderRadius: 10, borderWidth: 1, fontSize: 22, textAlign: 'center', fontVariant: ['tabular-nums'], paddingVertical: 8 },
  bar: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 16, paddingVertical: 10, borderTopWidth: StyleSheet.hairlineWidth },
  barVolume: { flex: 1 },
  barLabel: { fontSize: 12 },
  barValue: { fontSize: 20, fontWeight: '700', fontVariant: ['tabular-nums'] },
});

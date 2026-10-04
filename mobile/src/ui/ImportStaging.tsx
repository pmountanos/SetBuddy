import { useMemo, useState } from 'react';
import { Modal, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { importProgramReplacingStore } from '@/data/programImporter';
import { addDays, sameDate } from '@/domain/calendarDate';
import { matchCarryover, refKey } from '@/domain/carryoverMatcher';
import type { PickedWorkbook } from '@/settings/importExport';
import { useApp } from '@/state/AppContext';

import { formatDay } from './format';
import { Body, Button, Card, Divider, OptionSheet, Row, SectionTitle, Stepper } from './kit';
import { useTheme } from './theme';

/**
 * Shown after a workbook is picked, before anything is replaced: choose which worksheet day comes next and which
 * calendar day it lands on, and confirm which previous exercises the new ones continue from.
 */
export function ImportStaging({ workbook, onClose, onImported }: { workbook: PickedWorkbook; onClose: () => void; onImported: (message: string) => void }) {
  const theme = useTheme();
  const { services, refresh, setOpenWorkout } = useApp();
  const today = services.env.today();
  const { cycle, programName } = workbook;

  const match = useMemo(() => matchCarryover(services.programs.existingExercisesForCarryover(), cycle), [services, cycle]);
  const [cycleStartIndex, setCycleStartIndex] = useState(0);
  const [startOffset, setStartOffset] = useState(0);
  const [cyclePickerOpen, setCyclePickerOpen] = useState(false);
  const [accepted, setAccepted] = useState(() => match.suggestions.map(() => true));
  const [error, setError] = useState<string | null>(null);

  const startDate = addDays(today, startOffset);
  const dayLabel = (index: number) => `${index + 1}. ${cycle[index].sheetName}${cycle[index].isRestDay ? ' — Rest' : ''}`;
  const hasExistingProgram = services.programs.activeProgram() !== null;

  const runImport = () => {
    const carryover = new Map(match.autoCarryover);
    match.suggestions.forEach((suggestion, index) => {
      if (accepted[index]) carryover.set(refKey(suggestion.newExercise), suggestion.oldExerciseId);
    });
    try {
      importProgramReplacingStore(services.db, services.env, cycle, { programName, startDate, cycleStartIndex, exerciseCarryover: carryover });
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Import failed. Your current program was not changed.');
      return;
    }
    // Any open workout belonged to the program that was just replaced.
    setOpenWorkout(null);
    refresh();
    onImported(
      `Imported “${programName}”.` + (carryover.size > 0 ? ` Reference weights carried over for ${carryover.size} matching exercise${carryover.size === 1 ? '' : 's'}.` : ''),
    );
    onClose();
  };

  return (
    <Modal visible animationType="slide" presentationStyle="pageSheet" onRequestClose={onClose}>
      <SafeAreaView style={[styles.flex, { backgroundColor: theme.background }]}>
        <View style={styles.header}>
          <Button label="Cancel" kind="plain" compact onPress={onClose} />
          <Button label="Import" compact testID="importConfirm" onPress={runImport} />
        </View>
        <ScrollView contentContainerStyle={styles.content}>
          <Text style={[styles.title, { color: theme.text }]}>Import “{programName}”</Text>
          <Body secondary>
            {cycle.length} days in the rotation, {cycle.filter((day) => !day.isRestDay).length} of them workouts.
            {hasExistingProgram ? ' This replaces your current program and schedule. Completed workouts stay in History; a workout in progress is cleared.' : ''}
          </Body>
          {error ? <Text style={[styles.error, { color: theme.danger }]}>{error}</Text> : null}

          <SectionTitle>Where the rotation starts</SectionTitle>
          <Card>
            <Row onPress={() => setCyclePickerOpen(true)} trailing="Change">
              <Body secondary>Next day in the workbook</Body>
              <Body>{dayLabel(cycleStartIndex)}</Body>
            </Row>
            <Divider />
            <Stepper
              label={`Falls on ${sameDate(startDate, today) ? 'today' : formatDay(startDate)}`}
              value={startOffset}
              min={-14}
              max={60}
              onChange={setStartOffset}
            />
          </Card>

          {match.autoCarryover.size > 0 || match.suggestions.length > 0 ? (
            <>
              <SectionTitle>Carry over previous weights</SectionTitle>
              <Card style={styles.padded}>
                {match.autoCarryover.size > 0 ? (
                  <Body secondary>
                    {match.autoCarryover.size} exercise{match.autoCarryover.size === 1 ? '' : 's'} matched by name — reference weights carry over automatically.
                  </Body>
                ) : null}
                {match.suggestions.map((suggestion, index) => (
                  <View key={`${refKey(suggestion.newExercise)}-${index}`}>
                    <Divider />
                    <View style={styles.suggestion}>
                      <View style={styles.flex}>
                        <Body>{suggestion.newExercise.exerciseName}</Body>
                        <Body secondary style={styles.small}>
                          {suggestion.newExercise.workoutSheetName} · carry over from “{suggestion.oldExerciseName}”?
                        </Body>
                      </View>
                      <Switch
                        accessibilityLabel={`Carry over ${suggestion.oldExerciseName} to ${suggestion.newExercise.exerciseName}`}
                        value={accepted[index]}
                        onValueChange={(value) => setAccepted((current) => current.map((v, i) => (i === index ? value : v)))}
                      />
                    </View>
                  </View>
                ))}
              </Card>
            </>
          ) : null}
        </ScrollView>
        <OptionSheet
          visible={cyclePickerOpen}
          title="Which day in the workbook comes next?"
          onClose={() => setCyclePickerOpen(false)}
          options={cycle.map((_, index) => ({ label: dayLabel(index), selected: index === cycleStartIndex, onPress: () => setCycleStartIndex(index) }))}
        />
      </SafeAreaView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  header: { flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: 12, paddingTop: 12 },
  content: { padding: 16, gap: 12, paddingBottom: 48 },
  title: { fontSize: 24, fontWeight: '700' },
  error: { fontSize: 15, fontWeight: '600' },
  padded: { paddingVertical: 10 },
  suggestion: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 10 },
  small: { fontSize: 13, lineHeight: 18 },
});

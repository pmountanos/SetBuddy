import { Stack, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import type { HistorySetLine } from '@/data/historyRepository';
import { useApp, useData } from '@/state/AppContext';
import { formatFullDay, formatNumber, formatTimestamp, formatVolume } from '@/ui/format';
import { Body, Button, Card, Divider, EmptyState, SectionTitle, TextPrompt } from '@/ui/kit';
import { useTheme } from '@/ui/theme';

function setText(set: HistorySetLine): string {
  if (set.kind === 'cardio') return `${formatNumber(set.cardioMinutes)} min · max HR ${set.maxHeartRate}`;
  return `${formatNumber(set.weight)} kg × ${set.reps}${set.repsArePerSide ? ' /side' : ''}`;
}

export default function HistorySessionScreen() {
  const theme = useTheme();
  const { sessionId } = useLocalSearchParams<{ sessionId: string }>();
  const { services, refresh } = useApp();
  const detail = useData((s) => s.history.sessionDetail(sessionId));
  const [editingNote, setEditingNote] = useState(false);

  if (!detail) return <EmptyState title="Workout not found" message="This session is no longer in your history." />;

  return (
    <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={styles.content}>
      <Stack.Screen options={{ title: detail.title }} />
      <Card style={styles.summary}>
        <Text style={[styles.volume, { color: theme.text }]} testID="historyTotalVolume">
          {formatVolume(detail.totalVolume)} kg
        </Text>
        <Body secondary>Total volume</Body>
        <Body secondary>Completed {formatTimestamp(detail.completedAt)}</Body>
        <Body secondary>Scheduled for {formatFullDay(detail.scheduleDate)}</Body>
      </Card>

      {detail.exercises.map((exercise) => (
        <Card key={exercise.exerciseId} style={styles.exercise}>
          <View style={styles.exerciseHeader}>
            <Text style={[styles.exerciseName, { color: theme.text }]}>{exercise.name}</Text>
            <Text style={[styles.exerciseTotal, { color: theme.secondary }]}>
              {exercise.kind === 'cardio' ? `${formatNumber(exercise.cardioMinutes)} min` : `${formatVolume(exercise.volume)} kg`}
            </Text>
          </View>
          {exercise.sets.map((set) => (
            <View key={set.setNumber}>
              <Divider />
              <View style={styles.setRow}>
                <Text style={[styles.setLabel, { color: theme.secondary }]}>Set {set.setNumber}</Text>
                <Text style={[styles.setValue, { color: theme.text }]}>{setText(set)}</Text>
              </View>
            </View>
          ))}
        </Card>
      ))}
      {detail.exercises.length === 0 ? <Body secondary>No sets were entered for this workout.</Body> : null}

      <SectionTitle>Workout note</SectionTitle>
      <Card style={styles.summary}>
        <Body secondary={!detail.sessionNote}>{detail.sessionNote || 'No note.'}</Body>
        <Button label={detail.sessionNote ? 'Edit note' : 'Add a note'} kind="plain" compact onPress={() => setEditingNote(true)} />
      </Card>

      <TextPrompt
        visible={editingNote}
        title="Workout note"
        initialText={detail.sessionNote ?? ''}
        placeholder="How did it go?"
        onClose={() => setEditingNote(false)}
        onSave={(text) => {
          services.sessions.setSessionNote(detail.sessionId, text);
          refresh();
        }}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 12, paddingBottom: 48 },
  summary: { paddingVertical: 12, gap: 2 },
  volume: { fontSize: 32, fontWeight: '700', fontVariant: ['tabular-nums'] },
  exercise: { paddingVertical: 8 },
  exerciseHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', paddingVertical: 6, gap: 8 },
  exerciseName: { fontSize: 17, fontWeight: '600', flex: 1 },
  exerciseTotal: { fontSize: 14, fontVariant: ['tabular-nums'] },
  setRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 8 },
  setLabel: { fontSize: 15 },
  setValue: { fontSize: 16, fontVariant: ['tabular-nums'] },
});

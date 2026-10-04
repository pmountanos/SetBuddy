import { StatusBar } from 'expo-status-bar';
import { useEffect, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { type AppDatabase, appEnv, openAppDatabase } from './src/data/appDatabase';
import { HistoryRepository } from './src/data/historyRepository';
import { ProgramOutlineRepository } from './src/data/outlineRepository';

/**
 * Temporary diagnostic screen: opens the database (importing the native app's data on first launch) and lists
 * what it found, to prove the import on a device before the real screens exist.
 */
export default function App() {
  const [state, setState] = useState<{ app?: AppDatabase; error?: string }>({});

  useEffect(() => {
    openAppDatabase()
      .then((app) => setState({ app }))
      .catch((error: unknown) => setState({ error: error instanceof Error ? `${error.message}\n${error.stack}` : String(error) }));
  }, []);

  if (state.error) {
    return (
      <ScrollView contentContainerStyle={styles.container}>
        <Text style={styles.title} testID="status">Could not open the database</Text>
        <Text selectable>{state.error}</Text>
      </ScrollView>
    );
  }
  if (!state.app) {
    return (
      <View style={styles.container}>
        <Text testID="status">Opening…</Text>
      </View>
    );
  }

  const { db, legacyImport } = state.app;
  const outline = new ProgramOutlineRepository(db, appEnv).activeProgramOutline();
  const history = new HistoryRepository(db).completedRows();

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title} testID="status">Set Buddy — data check</Text>
      <Text testID="legacyImport">Legacy import: {JSON.stringify(legacyImport)}</Text>
      <Text style={styles.heading}>Program: {outline?.programName ?? 'none'}</Text>
      {outline?.workouts.map((workout) => (
        <Text key={workout.id}>
          {workout.name} — {workout.exercises.length} exercises
        </Text>
      ))}
      <Text style={styles.heading}>History ({history.length})</Text>
      {history.map((row) => (
        <Text key={row.sessionId}>
          {new Date(row.completedAt).toISOString().slice(0, 10)} · {row.title} · volume {Math.round(row.totalVolume)}
        </Text>
      ))}
      <StatusBar style="auto" />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { padding: 24, paddingTop: 72, gap: 6 },
  title: { fontSize: 22, fontWeight: '600' },
  heading: { fontSize: 17, fontWeight: '600', marginTop: 12 },
});

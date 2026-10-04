import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { useApp, useData } from '@/state/AppContext';
import { formatTimestamp, formatVolume } from '@/ui/format';
import { Card, Divider, EmptyState, Row, Screen } from '@/ui/kit';
import { useTheme } from '@/ui/theme';

export default function HistoryScreen() {
  const theme = useTheme();
  const router = useRouter();
  const { refresh } = useApp();
  useFocusEffect(useCallback(() => refresh(), [refresh]));
  const rows = useData((s) => s.history.completedRows(200));

  if (rows.length === 0) {
    return (
      <Screen scroll={false}>
        <EmptyState title="No completed workouts yet" message="Finish a workout and it will appear here with its total volume." />
      </Screen>
    );
  }

  return (
    <Screen title="History">
      <Card>
        {rows.map((row, index) => (
          <View key={row.sessionId}>
            {index > 0 ? <Divider /> : null}
            <Row
              testID={`historyRow-${index}`}
              onPress={() => router.push({ pathname: '/history/[sessionId]', params: { sessionId: row.sessionId } })}
              trailing={<Text style={[styles.volume, { color: theme.text }]}>{formatVolume(row.totalVolume)} kg</Text>}>
              <Text style={[styles.title, { color: theme.text }]}>{row.title}</Text>
              <Text style={[styles.meta, { color: theme.secondary }]}>
                {formatTimestamp(row.completedAt)}
                {row.hasSessionNote ? ' · Note' : ''}
              </Text>
            </Row>
          </View>
        ))}
      </Card>
    </Screen>
  );
}

const styles = StyleSheet.create({
  title: { fontSize: 17, fontWeight: '600' },
  meta: { fontSize: 13, marginTop: 2 },
  volume: { fontSize: 16, fontWeight: '600', fontVariant: ['tabular-nums'] },
});

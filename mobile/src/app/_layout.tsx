import { DarkTheme, DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useColorScheme } from 'react-native';

import { AppProvider, useAppServices } from '@/state/AppContext';
import { EmptyState, Screen } from '@/ui/kit';

export default function RootLayout() {
  const scheme = useColorScheme();
  const load = useAppServices();

  if (load.status !== 'ready') {
    return (
      <Screen scroll={false}>
        {load.status === 'loading' ? (
          <EmptyState title="Set Buddy" message="Opening your training log…" />
        ) : (
          <EmptyState title="Couldn’t open your training log" message={`${load.message}\n\nNothing was changed. Close the app and open it again to retry.`} />
        )}
      </Screen>
    );
  }

  return (
    <ThemeProvider value={scheme === 'dark' ? DarkTheme : DefaultTheme}>
      <AppProvider services={load.services}>
        <Stack>
          <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
          <Stack.Screen name="history/[sessionId]" options={{ title: 'Workout', headerBackTitle: 'History' }} />
        </Stack>
        <StatusBar style="auto" />
      </AppProvider>
    </ThemeProvider>
  );
}

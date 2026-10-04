import { createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useState } from 'react';

import { type AppDatabase, appEnv, type LegacyImport, openAppDatabase } from '@/data/appDatabase';
import type { Db } from '@/data/db';
import { HistoryRepository } from '@/data/historyRepository';
import type { Env } from '@/data/models';
import { ProgramOutlineRepository } from '@/data/outlineRepository';
import { ProgramRepository } from '@/data/programRepository';
import { WorkoutSessionRepository } from '@/data/sessionRepository';
import type { CalendarDate } from '@/domain/calendarDate';

export interface Services {
  db: Db;
  env: Env;
  programs: ProgramRepository;
  outlines: ProgramOutlineRepository;
  sessions: WorkoutSessionRepository;
  history: HistoryRepository;
  legacyImport: LegacyImport;
}

/** The workout the Workout tab is logging. */
export interface OpenWorkout {
  workoutId: string;
  date: CalendarDate;
}

interface AppState {
  services: Services;
  /** Changes whenever stored data may have changed; screens re-read when it does. */
  version: number;
  /** Call after any write so every screen picks up the change. */
  refresh(): void;
  openWorkout: OpenWorkout | null;
  setOpenWorkout(workout: OpenWorkout | null): void;
}

const AppContext = createContext<AppState | null>(null);

function buildServices({ db, legacyImport }: AppDatabase): Services {
  return {
    db,
    env: appEnv,
    programs: new ProgramRepository(db, appEnv),
    outlines: new ProgramOutlineRepository(db, appEnv),
    sessions: new WorkoutSessionRepository(db, appEnv),
    history: new HistoryRepository(db),
    legacyImport,
  };
}

export type AppLoadState = { status: 'loading' } | { status: 'failed'; message: string } | { status: 'ready'; services: Services };

/** Opens the database once (importing the previous native app's data on first launch). */
export function useAppServices(): AppLoadState {
  const [state, setState] = useState<AppLoadState>({ status: 'loading' });
  useEffect(() => {
    openAppDatabase()
      .then((database) => setState({ status: 'ready', services: buildServices(database) }))
      .catch((error: unknown) => setState({ status: 'failed', message: error instanceof Error ? error.message : String(error) }));
  }, []);
  return state;
}

export function AppProvider({ services, children }: { services: Services; children: ReactNode }) {
  const [version, setVersion] = useState(0);
  const [openWorkout, setOpenWorkout] = useState<OpenWorkout | null>(null);
  const refresh = useCallback(() => setVersion((v) => v + 1), []);
  const value = useMemo(() => ({ services, version, refresh, openWorkout, setOpenWorkout }), [services, version, refresh, openWorkout]);
  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}

export function useApp(): AppState {
  const state = useContext(AppContext);
  if (!state) throw new Error('useApp must be used inside AppProvider');
  return state;
}

/** Reads from the repositories, re-reading whenever stored data changes. */
export function useData<T>(read: (services: Services) => T): T {
  const { services, version } = useApp();
  // eslint-disable-next-line react-hooks/exhaustive-deps -- `version` is the invalidation signal; `read` is an inline closure
  return useMemo(() => read(services), [services, version]);
}
